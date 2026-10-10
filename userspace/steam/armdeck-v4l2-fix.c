/*
 * armdeck-v4l2-fix (armdeck): a preload for Steam's ARM64 Remote Play client
 * (steamrtarm64/streaming_client) on the SM8250 Venus decoder. Two client assumptions do not hold
 * on Venus:
 *
 * 1. The client keeps its CAPTURE buffers (DRM dumb buffers) in a fixed table of 16. Venus
 *    answers REQBUFS 16 with 18 (output_buffer_count() in hfi_plat_bufs_v6.c), the client fills
 *    18 entries and overwrites its own OUTPUT buffer list: crash before the first frame. Fix:
 *    report at most 16 CAPTURE buffers back.
 *
 * 2. The client starts both queues and queues its CAPTURE buffers before the first frame, and
 *    never subscribes to V4L2 events. Venus ignores that early CAPTURE start (codec state INIT),
 *    sends V4L2_EVENT_SOURCE_CHANGE once the first frame's headers are parsed, and waits for the
 *    capture setup (STREAMOFF, REQBUFS, STREAMON on CAPTURE). The client times out after about
 *    36 ms, restarts both queues and loops. Fix: subscribe for the client, wait for the event
 *    right after its first OUTPUT buffer, do the capture setup, and queue the client's CAPTURE
 *    buffers again (same index, same dmabuf).
 *
 * Every step goes to /tmp/armdeck-v4l2-fix.log. op8-remoteplay builds this file in the steam
 * container and puts a wrapper in front of the client that loads it with LD_PRELOAD.
 * Found and tested on 2026-10-10/11 (docs/gaming-stack.md, TODO 11).
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <poll.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <linux/videodev2.h>

#define MAX_CAPTURE 16
#define MAX_FD 1024
#define MAX_BUF 32
#define FIRST_EVENT_WAIT_MS 300

struct capbuf {
	int queued;
	struct v4l2_buffer b;
	struct v4l2_plane p[VIDEO_MAX_PLANES];
};

struct dec {
	int subscribed;
	int need_first;		/* CAPTURE was started by the client: wait for the event */
	unsigned int cap_count;	/* what the client asked REQBUFS for */
	unsigned int cap_memory;
	struct capbuf cap[MAX_BUF];
};

static struct dec *decs[MAX_FD];
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static int (*real)(int, unsigned long, ...);

static void note(const char *fmt, ...)
{
	FILE *f = fopen("/tmp/armdeck-v4l2-fix.log", "a");
	struct timespec ts;
	va_list ap;

	if (!f)
		return;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	fprintf(f, "%ld.%03ld ", (long)ts.tv_sec, ts.tv_nsec / 1000000);
	va_start(ap, fmt);
	vfprintf(f, fmt, ap);
	va_end(ap);
	fputc('\n', f);
	fclose(f);
}

static struct dec *get_dec(int fd)
{
	if (fd < 0 || fd >= MAX_FD)
		return NULL;
	if (!decs[fd])
		decs[fd] = calloc(1, sizeof(struct dec));
	return decs[fd];
}

static int is_cap(unsigned int type)
{
	return type == V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE || type == V4L2_BUF_TYPE_VIDEO_CAPTURE;
}

static int is_out(unsigned int type)
{
	return type == V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE || type == V4L2_BUF_TYPE_VIDEO_OUTPUT;
}

/* the capture setup Venus waits for, done with the client's own buffers; lock held */
static void capture_setup(int fd, struct dec *d)
{
	unsigned int t = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
	struct v4l2_format fmt = { .type = t };
	struct v4l2_requestbuffers rb = { .type = t };
	int r_off, r_req, r_on, ok = 0, bad = 0, i;

	if (real(fd, VIDIOC_G_FMT, &fmt) == 0)
		note("fd %d: capture format %ux%u %.4s, plane 0 %u bytes, stride %u", fd,
		     fmt.fmt.pix_mp.width, fmt.fmt.pix_mp.height,
		     (char *)&fmt.fmt.pix_mp.pixelformat, fmt.fmt.pix_mp.plane_fmt[0].sizeimage,
		     fmt.fmt.pix_mp.plane_fmt[0].bytesperline);
	r_off = real(fd, VIDIOC_STREAMOFF, &t);
	rb.count = d->cap_count ? d->cap_count : MAX_CAPTURE;
	rb.memory = d->cap_memory ? d->cap_memory : V4L2_MEMORY_DMABUF;
	r_req = real(fd, VIDIOC_REQBUFS, &rb);
	r_on = real(fd, VIDIOC_STREAMON, &t);
	for (i = 0; i < MAX_BUF; i++) {
		struct v4l2_buffer b;
		struct v4l2_plane p[VIDEO_MAX_PLANES];

		if (!d->cap[i].queued)
			continue;
		b = d->cap[i].b;
		memcpy(p, d->cap[i].p, sizeof(p));
		if (b.type == V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE)
			b.m.planes = p;
		if (real(fd, VIDIOC_QBUF, &b) == 0) {
			ok++;
		} else {
			bad++;
			d->cap[i].queued = 0;
		}
	}
	note("fd %d: capture setup: streamoff %d, reqbufs %d (count %u), streamon %d, "
	     "requeued %d, failed %d", fd, r_off, r_req, rb.count, r_on, ok, bad);
}

/* after an OUTPUT buffer: handle a pending source change (wait for it after a CAPTURE start) */
static void check_event(int fd, struct dec *d)
{
	int wait_ms = d->need_first ? FIRST_EVENT_WAIT_MS : 0;
	struct pollfd pfd = { .fd = fd, .events = POLLPRI };
	struct v4l2_event ev;
	int got = 0, pr;

	pr = poll(&pfd, 1, wait_ms);
	if (pr > 0 && (pfd.revents & POLLPRI)) {
		pthread_mutex_lock(&lock);
		while (real(fd, VIDIOC_DQEVENT, &ev) == 0) {
			if (ev.type == V4L2_EVENT_SOURCE_CHANGE)
				got = 1;
			note("fd %d: event %u (changes 0x%x)", fd, ev.type,
			     ev.u.src_change.changes);
			if (!ev.pending)
				break;
		}
		if (got)
			capture_setup(fd, d);
		d->need_first = 0;
		pthread_mutex_unlock(&lock);
	} else if (d->need_first) {
		note("fd %d: no source change within %d ms", fd, wait_ms);
		d->need_first = 0;
	}
}

int ioctl(int fd, unsigned long req, ...)
{
	va_list ap;
	void *arg;
	struct dec *d;
	int r;

	va_start(ap, req);
	arg = va_arg(ap, void *);
	va_end(ap);
	if (!real)
		real = (int (*)(int, unsigned long, ...))dlsym(RTLD_NEXT, "ioctl");
	if (!arg)
		return real(fd, req, arg);

	switch (req) {
	case VIDIOC_REQBUFS: {
		struct v4l2_requestbuffers *rb = arg;
		unsigned int asked = rb->count;

		r = real(fd, req, arg);
		if (r == 0 && is_cap(rb->type) && (d = get_dec(fd))) {
			pthread_mutex_lock(&lock);
			memset(d->cap, 0, sizeof(d->cap));
			d->cap_count = asked;
			d->cap_memory = rb->memory;
			pthread_mutex_unlock(&lock);
			if (rb->count > MAX_CAPTURE) {
				note("fd %d: CAPTURE REQBUFS asked %u, driver gave %u, reported %u",
				     fd, asked, rb->count, MAX_CAPTURE);
				rb->count = MAX_CAPTURE;
			}
		}
		return r;
	}
	case VIDIOC_STREAMON: {
		unsigned int t = *(unsigned int *)arg;

		r = real(fd, req, arg);
		if (r == 0 && (d = get_dec(fd))) {
			if (!d->subscribed) {
				struct v4l2_event_subscription sub = {
					.type = V4L2_EVENT_SOURCE_CHANGE };

				d->subscribed = 1;
				note("fd %d: subscribe source change: %d", fd,
				     real(fd, VIDIOC_SUBSCRIBE_EVENT, &sub));
			}
			if (is_cap(t))
				d->need_first = 1;
		}
		return r;
	}
	case VIDIOC_STREAMOFF: {
		unsigned int t = *(unsigned int *)arg;

		r = real(fd, req, arg);
		if (r == 0 && is_cap(t) && (d = get_dec(fd))) {
			int i;

			pthread_mutex_lock(&lock);
			for (i = 0; i < MAX_BUF; i++)
				d->cap[i].queued = 0;
			pthread_mutex_unlock(&lock);
		}
		return r;
	}
	case VIDIOC_QBUF: {
		struct v4l2_buffer *b = arg;
		struct v4l2_buffer copy = *b;
		struct v4l2_plane planes[VIDEO_MAX_PLANES];

		if (b->type == V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE && b->m.planes &&
		    b->length <= VIDEO_MAX_PLANES)
			memcpy(planes, b->m.planes, b->length * sizeof(planes[0]));
		r = real(fd, req, arg);
		if (r != 0 || !(d = get_dec(fd)))
			return r;
		if (is_cap(copy.type) && copy.index < MAX_BUF) {
			pthread_mutex_lock(&lock);
			d->cap[copy.index].queued = 1;
			d->cap[copy.index].b = copy;
			if (copy.type == V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE)
				memcpy(d->cap[copy.index].p, planes,
				       copy.length * sizeof(planes[0]));
			pthread_mutex_unlock(&lock);
		} else if (is_out(copy.type) && d->subscribed) {
			check_event(fd, d);
		}
		return r;
	}
	case VIDIOC_DQBUF: {
		struct v4l2_buffer *b = arg;

		r = real(fd, req, arg);
		if (r == 0 && is_cap(b->type) && b->index < MAX_BUF && (d = get_dec(fd))) {
			pthread_mutex_lock(&lock);
			d->cap[b->index].queued = 0;
			pthread_mutex_unlock(&lock);
		}
		return r;
	}
	default:
		return real(fd, req, arg);
	}
}
