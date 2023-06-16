import kong_pdk.pdk.kong as kong
from guppy import hpy

Schema = []
version = "0.0.1"
priority = 100


class Plugin():

    def __init__(self, config):
        self.h = hpy()
        self.h.setref()

    def access(self, kong: kong.kong):
        if kong.request.get_query_arg("dump_heap"):
            kong.log.info("Dumping heap...")
            heap_by_type = self.h.heap().bytype
            heap_by_rcs = heap_by_type[0].byrcs
            print(heap_by_type, flush=True)
            print(heap_by_rcs, flush=True)
            kong.log.info("Dumping heap done")
