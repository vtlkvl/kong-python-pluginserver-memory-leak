#!/bin/bash

cd /home/kong && poetry run kong-python-pluginserver --plugins-directory /home/kong/plugins --no-lua-style "$@"
