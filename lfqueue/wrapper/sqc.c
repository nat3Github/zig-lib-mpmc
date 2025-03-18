#include "sqc.h"
#include "../lfring_cas1.h"

const size_t SQC_EMPTY_DEQUEUE = LFRING_EMPTY;

void sqc_init(struct lfring *ring, size_t order) {
  return lfring_init_empty(ring, order);
}

bool sqc_enqueue(struct lfring *ring, size_t order, size_t val) {
  size_t eidx = (size_t)val;
  return lfring_enqueue(ring, order, eidx, false);
}

size_t sqc_dequeue(struct lfring *ring, size_t order) {
  return lfring_dequeue(ring, order, false);
}

size_t sqc_size(size_t order) { return LFRING_SIZE(order); }