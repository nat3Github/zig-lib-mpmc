#include "wqc.h"
#include "../wfring_cas2.h"

void wqc_init(struct wfring *ring, size_t order) {
  return wfring_init_empty(ring, order);
}

void wqc_enque(struct wfring *ring, size_t order, size_t eidx, bool nonempty,
               struct wfring_state *state) {
  return wfring_enqueue(ring, order, eidx, nonempty, state);
}

size_t wqc_deque(struct wfring *ring, size_t order, bool nonempty,
                 struct wfring_state *state) {
  return wfring_dequeue(ring, order, nonempty, state);
}
