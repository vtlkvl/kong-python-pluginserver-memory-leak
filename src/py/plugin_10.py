import kong_pdk.pdk.kong as kong

Schema = []
version = "0.0.1"
priority = 100


class Plugin():

    def __init__(self, config):
        pass

    def access(self, kong: kong.kong):
        pass
