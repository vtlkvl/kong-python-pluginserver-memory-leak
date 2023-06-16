# Synopsis
While testing custom Python-based Kong plugins we discovered a very bad memory issue in Kong Plugin 
Server which is a part of [Kong PDK](https://github.com/Kong/kong-python-pdk). We noticed that a few
days after Kong was deployed to one of the environments with a pretty moderate load the memory usage
was gradually growing and the pod crashed with OOM in the end. After detailed investigation we were
able to confirm that there is no memory leak in our code, but rather something was wrong with Kong
and more specifically Python environment.

### Environment
1. [Kong 3.2.2 (Ubuntu)](https://hub.docker.com/layers/library/kong/3.2.2-ubuntu/images/sha256-0ecd93ecf2e1335859e9c57b7baf43f97a63906df220cbd8334bc20af0f80bf5)
2. [Kong PDK 0.33](https://pypi.org/project/kong-pdk/)
3. Python 3.10.6

# Memory Analysis
We will run a test the goal of which is to see how memory is used under the load. We will deploy
Kong locally with 10 plugins with no-op `access` handler. We will also create a single ingress 
mapped to `/echo` that we will hit with `siege`. Besides, we can call it with `dump_heap` parameter
that will log statistics per object type, and we will see how it changes over the time.

### Prerequisites
Running Kong locally will require a pretty standard toolkit:
1. [Docker Desktop](https://www.docker.com/products/docker-desktop/)
2. [KinD](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
3. [Helm](https://helm.sh/docs/intro/install/)

## Test
1. Start Kong.
```sh
./kong-local.sh stop start
...
Image: "kong-gateway:1.0.0" with ID "sha256:f3da8db5cb07db5e9cf568519492e15bacd5744f650d54e0910dbe92596fdd47" not yet present on node "kind-control-plane", loading...
Getting updates for unmanaged Helm repositories...
...Successfully got an update from the "https://charts.konghq.com" chart repository
Saving 1 charts
Downloading kong from repo https://charts.konghq.com
Deleting outdated charts
NAME: kong
LAST DEPLOYED: Fri Jun 16 15:14:00 2023
NAMESPACE: default
STATUS: deployed
REVISION: 1
TEST SUITE: None
Forwarding from 0.0.0.0:8080 -> 8000
```
2. Run `siege` with 20 concurrent users for 30 seconds and dump heap before and after. Repeat it a few times.
```shell
$ curl -S -s -o /dev/null 'http://localhost:8080/echo?dump_heap'

$ kubectl logs kong-kong-557cffcf5-xqf7t -n kong -c proxy | grep -A 20 "Dumping heap\.\.\." | tail -n 20
2023/06/16 12:25:26 [info] 1267#0: *522 [kong] mp_rpc.lua:157 [plugin_1] Dumping heap..., client: 127.0.0.1, server: kong, request: "GET /echo?dump_heap HTTP/1.1", host: "localhost:8080"
2023/06/16 12:25:26 [info] 1267#0: *298 [python:1269] Partition of a set of 86 objects. Total size = 13804 bytes., context: ngx.timer
2023/06/16 12:25:26 [info] 1267#0: *298 [python:1269]  Index  Count   %     Size   % Cumulative  % Type, context: ngx.timer
2023/06/16 12:25:26 [info] 1267#0: *298 [python:1269]      0      9  10     5616  41      5616  41 collections.deque, context: ngx.timer
2023/06/16 12:25:26 [info] 1267#0: *298 [python:1269]      1      6   7     2600  19      8216  60 types.FrameType, context: ngx.timer
2023/06/16 12:25:26 [info] 1267#0: *298 [python:1269]      2     15  17     2176  16     10392  75 dict, context: ngx.timer
2023/06/16 12:25:26 [info] 1267#0: *298 [python:1269]      3     14  16     1008   7     11400  83 types.BuiltinMethodType, context: ngx.timer
2023/06/16 12:25:26 [info] 1267#0: *298 [python:1269]      4      3   3      432   3     11832  86 function, context: ngx.timer
2023/06/16 12:25:26 [info] 1267#0: *298 [python:1269]      5      7   8      336   2     12168  88 threading.Condition, context: ngx.timer
2023/06/16 12:25:26 [info] 1267#0: *298 [python:1269]      6      5   6      280   2     12448  90 _thread.lock, context: ngx.timer
2023/06/16 12:25:26 [info] 1267#0: *298 [python:1269]      7      7   8      280   2     12728  92 types.CellType, context: ngx.timer
2023/06/16 12:25:26 [info] 1267#0: *298 [python:1269]      8      4   5      256   2     12984  94 types.MethodType, context: ngx.timer
2023/06/16 12:25:26 [info] 1267#0: *298 [python:1269]      9      3   3      200   1     13184  96 tuple, context: ngx.timer
2023/06/16 12:25:26 [info] 1267#0: *298 [python:1269] <9 more rows. Type e.g. '_.more' to view.>, context: ngx.timer
2023/06/16 12:25:26 [info] 1267#0: *298 [python:1269] Partition of a set of 9 objects. Total size = 5616 bytes., context: ngx.timer
2023/06/16 12:25:26 [info] 1267#0: *298 [python:1269]  Index  Count   %     Size   % Cumulative  % Referrers by Kind (class / dict of class), context: ngx.timer
2023/06/16 12:25:26 [info] 1267#0: *298 [python:1269]      0      7  78     4368  78      4368  78 dict of threading.Condition, context: ngx.timer
2023/06/16 12:25:26 [info] 1267#0: *298 [python:1269]      1      2  22     1248  22      5616 100 dict of queue.Queue, context: ngx.timer
2023/06/16 12:25:26 [info] 1267#0: *522 [kong] mp_rpc.lua:157 [plugin_1] Dumping heap done, client: 127.0.0.1, server: kong, request: "GET /echo?dump_heap HTTP/1.1", host: "localhost:8080"
127.0.0.1 - - [16/Jun/2023:12:25:26 +0000] "GET /echo?dump_heap HTTP/1.1" 200 1575 "-" "-"

$ siege -q -c 20 -t 30S -i http://localhost:8080/echo

$ curl -S -s -o /dev/null 'http://localhost:8080/echo?dump_heap'

$ kubectl logs kong-kong-557cffcf5-xqf7t -n kong -c proxy | grep -A 20 "Dumping heap\.\.\." | tail -n 20
127.0.0.1 - - [16/Jun/2023:12:36:13 +0000] "GET /status HTTP/2.0" 200 1072 "-" "Go-http-client/2.0"
2023/06/16 12:36:13 [info] 1267#0: *298 [python:1269] Partition of a set of 3178898 objects. Total size = 575238938 bytes., context: ngx.timer
2023/06/16 12:36:13 [info] 1267#0: *298 [python:1269]  Index  Count   %     Size   % Cumulative  % Type, context: ngx.timer
2023/06/16 12:36:13 [info] 1267#0: *298 [python:1269]      0 620109  20 386948016  67 386948016  67 collections.deque, context: ngx.timer
2023/06/16 12:36:13 [info] 1267#0: *298 [python:1269]      1 620281  20 70734752  12 457682768  80 dict, context: ngx.timer
2023/06/16 12:36:13 [info] 1267#0: *298 [python:1269]      2 930182  29 66973104  12 524655872  91 types.BuiltinMethodType, context: ngx.timer
2023/06/16 12:36:13 [info] 1267#0: *298 [python:1269]      3 465091  15 22324368   4 546980240  95 threading.Condition, context: ngx.timer
2023/06/16 12:36:13 [info] 1267#0: *298 [python:1269]      4 155066   5  9924224   2 556904464  97 types.MethodType, context: ngx.timer
2023/06/16 12:36:13 [info] 1267#0: *298 [python:1269]      5 155093   5  8685208   2 565589672  98 _thread.lock, context: ngx.timer
2023/06/16 12:36:13 [info] 1267#0: *298 [python:1269]      6 155018   5  7440864   1 573030536 100 queue.Queue, context: ngx.timer
2023/06/16 12:36:13 [info] 1267#0: *298 [python:1269]      7  77440   2  2168508   0 575199044 100 int, context: ngx.timer
2023/06/16 12:36:13 [info] 1267#0: *298 [python:1269]      8    187   0     7480   0 575206524 100 types.CellType, context: ngx.timer
2023/06/16 12:36:13 [info] 1267#0: *298 [python:1269]      9     40   0     5760   0 575212284 100 function, context: ngx.timer
2023/06/16 12:36:13 [info] 1267#0: *298 [python:1269] <22 more rows. Type e.g. '_.more' to view.>, context: ngx.timer
127.0.0.1 - - [16/Jun/2023:12:36:16 +0000] "GET /status HTTP/2.0" 200 1072 "-" "Go-http-client/2.0"
127.0.0.1 - - [16/Jun/2023:12:36:19 +0000] "GET /status HTTP/2.0" 200 1072 "-" "Go-http-client/2.0"
2023/06/16 12:36:20 [info] 1267#0: *298 [python:1269] Partition of a set of 620109 objects. Total size = 386948016 bytes., context: ngx.timer
2023/06/16 12:36:20 [info] 1267#0: *298 [python:1269]  Index  Count   %     Size   % Cumulative  % Referrers by Kind (class / dict of class), context: ngx.timer
2023/06/16 12:36:20 [info] 1267#0: *298 [python:1269]      0 465091  75 290216784  75 290216784  75 dict of threading.Condition, context: ngx.timer
2023/06/16 12:36:20 [info] 1267#0: *298 [python:1269]      1 155018  25 96731232  25 386948016 100 dict of queue.Queue, context: ngx.timer

$ siege -q -c 20 -t 30S -i http://localhost:8080/echo

$ curl -S -s -o /dev/null 'http://localhost:8080/echo?dump_heap'

$ kubectl logs kong-kong-557cffcf5-xqf7t -n kong -c proxy | grep -A 20 "Dumping heap\.\.\." | tail -n 20
2023/06/16 12:43:26 [info] 1267#0: *26481 [kong] mp_rpc.lua:157 [plugin_1] Dumping heap..., client: 127.0.0.1, server: kong, request: "GET /echo?dump_heap HTTP/1.1", host: "localhost:8080"
127.0.0.1 - - [16/Jun/2023:12:43:28 +0000] "GET /status HTTP/2.0" 200 1075 "-" "Go-http-client/2.0"
127.0.0.1 - - [16/Jun/2023:12:43:31 +0000] "GET /status HTTP/2.0" 200 1075 "-" "Go-http-client/2.0"
2023/06/16 12:43:32 [info] 1267#0: *298 [python:1269] Partition of a set of 9338752 objects. Total size = 1690041325 bytes., context: ngx.timer
2023/06/16 12:43:32 [info] 1267#0: *298 [python:1269]  Index  Count   %     Size   % Cumulative  % Type, context: ngx.timer
2023/06/16 12:43:32 [info] 1267#0: *298 [python:1269]      0 1822075  20 1136974800  67 1136974800  67 collections.deque, context: ngx.timer
2023/06/16 12:43:32 [info] 1267#0: *298 [python:1269]      1 1822173  20 207747048  12 1344721848  80 dict, context: ngx.timer
2023/06/16 12:43:32 [info] 1267#0: *298 [python:1269]      2 2733130  29 196785360  12 1541507208  91 types.BuiltinMethodType, context: ngx.timer
2023/06/16 12:43:32 [info] 1267#0: *298 [python:1269]      3 1366565  15 65595120   4 1607102328  95 threading.Condition, context: ngx.timer
2023/06/16 12:43:32 [info] 1267#0: *298 [python:1269]      4 455523   5 29153472   2 1636255800  97 types.MethodType, context: ngx.timer
2023/06/16 12:43:32 [info] 1267#0: *298 [python:1269]      5 455581   5 25512536   2 1661768336  98 _thread.lock, context: ngx.timer
2023/06/16 12:43:32 [info] 1267#0: *298 [python:1269]      6 455510   5 21864480   1 1683632816 100 queue.Queue, context: ngx.timer
2023/06/16 12:43:32 [info] 1267#0: *298 [python:1269]      7 227682   2  6375276   0 1690008092 100 int, context: ngx.timer
2023/06/16 12:43:32 [info] 1267#0: *298 [python:1269]      8    177   0     7080   0 1690015172 100 types.CellType, context: ngx.timer
2023/06/16 12:43:32 [info] 1267#0: *298 [python:1269]      9     38   0     5472   0 1690020644 100 function, context: ngx.timer
2023/06/16 12:43:32 [info] 1267#0: *298 [python:1269] <22 more rows. Type e.g. '_.more' to view.>, context: ngx.timer
127.0.0.1 - - [16/Jun/2023:12:43:34 +0000] "GET /status HTTP/2.0" 200 1075 "-" "Go-http-client/2.0"
127.0.0.1 - - [16/Jun/2023:12:43:37 +0000] "GET /status HTTP/2.0" 200 1075 "-" "Go-http-client/2.0"
2023/06/16 12:43:51 [info] 1267#0: *298 [python:1269] Partition of a set of 1822075 objects. Total size = 1136974800 bytes., context: ngx.timer
2023/06/16 12:43:51 [info] 1267#0: *298 [python:1269]  Index  Count   %     Size   % Cumulative  % Referrers by Kind (class / dict of class), context: ngx.timer
2023/06/16 12:43:51 [info] 1267#0: *298 [python:1269]      0 1366565  75 852736560  75 852736560  75 dict of threading.Condition, context: ngx.timer
2023/06/16 12:43:51 [info] 1267#0: *298 [python:1269]      1 455510  25 284238240  25 1136974800 100 dict of queue.Queue, context: ngx.timer
2023/06/16 12:43:51 [info] 1267#0: *26481 [kong] mp_rpc.lua:157 [plugin_1] Dumping heap done, client: 127.0.0.1, server: kong, request: "GET /echo?dump_heap HTTP/1.1", host: "localhost:8080"
127.0.0.1 - - [16/Jun/2023:12:43:51 +0000] "GET /echo?dump_heap HTTP/1.1" 200 1246 "-" "curl/7.86.0"
```
The first table contains top allocations by type. The second table shows references to the top most 
type from the first table. In each table we can see the total number of allocations, the amount of
memory currently used by a specific type and the total amount of memory allocated during the whole
period. It's clearly obvious that `collections.deque` never gets cleaned up. `collections.deque` is
used by `queue.Queue` and `threading.Condition`. `queue.Queue` are heavily used in [Kong Plugin Server](https://github.com/Kong/kong-python-pdk/blob/master/kong_pdk/server.py#L302-L303)
to exchange messages with plugins and `threading.Condition` is used by `queue.Queue`. Switching to
`gevent` does not help either because [Channel](https://github.com/gevent/gevent/blob/master/src/gevent/queue.py#L581-L582)
uses `collections.deque` as well and we were able to reproduce the same issue.

# Conclusion
It is not very clear if it is a Python issue or Kong uses `collections.deque` in the way that is not
supposed to be used. A similar [bug](https://bugs.python.org/issue43911) was reported for Python and
it has been already resolved without a clear resolution.