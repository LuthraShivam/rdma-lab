## RDMA devices

RDMA devices are global to all network namespaces when the RDMA subsystem mode is set to shared (default)

RDMA devices can be assigned to a dedicated network namespace using rdma dev set [DEV] netns [NSNAME|PID]. This mode must be set before creating network namespaces while no active RDMA traffic is running

List RDMA devices:

```
rdma dev show
rdma dev show <rdma device name>
```

More details:

```
ls /sys/class/infiniband/
cat /sys/class/infiniband/rxe-a/ports/1/gids/{0,1}
```

The GIDs (the RDMA addresses) are derived from the interface's IP addresses, so they also show the binding. Index 0 should be the IPv6 link-local address.

Another index should hold the IPv4-mapped address ::ffff:10.0.0.1. (index 1)


Checking if RoCE socket exists inside namespace:
`sudo ip netns exec ns-a ss -ulnp | grep 4791`

## RDMA Ping Pong test

```
lab@rdma-a:~$ ibv_rc_pingpong -d rxe0 -g 1
  local address:  LID 0x0000, QPN 0x000015, PSN 0x9ddebe, GID ::ffff:192.168.124.224
  remote address: LID 0x0000, QPN 0x000014, PSN 0xe30ccd, GID ::ffff:192.168.124.208
8192000 bytes in 0.06 seconds = 1157.86 Mbit/sec
1000 iters in 0.06 seconds = 56.60 usec/iter
lab@rdma-a:~$
```

```
lab@rdma-b:~$ ibv_rc_pingpong -d rxe0 -g 1 192.168.124.224
  local address:  LID 0x0000, QPN 0x000014, PSN 0xe30ccd, GID ::ffff:192.168.124.208
  remote address: LID 0x0000, QPN 0x000015, PSN 0x9ddebe, GID ::ffff:192.168.124.224
8192000 bytes in 0.06 seconds = 1158.04 Mbit/sec
1000 iters in 0.06 seconds = 56.59 usec/iter
lab@rdma-b:~$
```

## Baseline Write Test:

```
lab@rdma-a:~$ ib_write_bw -d rxe0

************************************
* Waiting for client to connect... *
************************************
---------------------------------------------------------------------------------------
                    RDMA_Write BW Test
 Dual-port       : OFF          Device         : rxe0
 Number of qps   : 1            Transport type : IB
 Connection type : RC           Using SRQ      : OFF
 PCIe relax order: ON
 ibv_wr* API     : OFF
 CQ Moderation   : 1
 Mtu             : 1024[B]
 Link type       : Ethernet
 GID index       : 1
 Max inline data : 0[B]
 rdma_cm QPs     : OFF
 Data ex. method : Ethernet
---------------------------------------------------------------------------------------
 local address: LID 0000 QPN 0x0013 PSN 0x1b7e09 RKey 0x00045b VAddr 0x007007ccea5000
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:192:168:124:224
 remote address: LID 0000 QPN 0x0012 PSN 0x9f225d RKey 0x00036f VAddr 0x00722b2a042000
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:192:168:124:208
---------------------------------------------------------------------------------------
 #bytes     #iterations    BW peak[MB/sec]    BW average[MB/sec]   MsgRate[Mpps]
 65536      5000             446.05             430.03             0.006880
---------------------------------------------------------------------------------------
lab@rdma-a:~$
```


```
lab@rdma-b:~$ ib_write_bw -d rxe0 192.168.124.224
---------------------------------------------------------------------------------------
                    RDMA_Write BW Test
 Dual-port       : OFF          Device         : rxe0
 Number of qps   : 1            Transport type : IB
 Connection type : RC           Using SRQ      : OFF
 PCIe relax order: ON
 ibv_wr* API     : OFF
 TX depth        : 128
 CQ Moderation   : 1
 Mtu             : 1024[B]
 Link type       : Ethernet
 GID index       : 1
 Max inline data : 0[B]
 rdma_cm QPs     : OFF
 Data ex. method : Ethernet
---------------------------------------------------------------------------------------
 local address: LID 0000 QPN 0x0012 PSN 0x9f225d RKey 0x00036f VAddr 0x00722b2a042000
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:192:168:124:208
 remote address: LID 0000 QPN 0x0013 PSN 0x1b7e09 RKey 0x00045b VAddr 0x007007ccea5000
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:192:168:124:224
---------------------------------------------------------------------------------------
 #bytes     #iterations    BW peak[MB/sec]    BW average[MB/sec]   MsgRate[Mpps]
 65536      5000             446.05             430.03             0.006880
---------------------------------------------------------------------------------------
lab@rdma-b:~$
```

## Baseline Latency Test

```
lab@rdma-a:~$ ib_send_lat -d rxe0

************************************
* Waiting for client to connect... *
************************************
---------------------------------------------------------------------------------------
                    Send Latency Test
 Dual-port       : OFF          Device         : rxe0
 Number of qps   : 1            Transport type : IB
 Connection type : RC           Using SRQ      : OFF
 PCIe relax order: ON
 ibv_wr* API     : OFF
 RX depth        : 512
 Mtu             : 1024[B]
 Link type       : Ethernet
 GID index       : 1
 Max inline data : 0[B]
 rdma_cm QPs     : OFF
 Data ex. method : Ethernet
---------------------------------------------------------------------------------------
 local address: LID 0000 QPN 0x0014 PSN 0x3bbebe
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:192:168:124:224
 remote address: LID 0000 QPN 0x0013 PSN 0x2d2d36
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:192:168:124:208
---------------------------------------------------------------------------------------
 #bytes #iterations    t_min[usec]    t_max[usec]  t_typical[usec]    t_avg[usec]    t_stdev[usec]   99% percentile[usec]   99.9% percentile[usec]
 2       1000          17.40          40.51        21.60               21.94            1.38    26.76            40.51
---------------------------------------------------------------------------------------
lab@rdma-a:~$
```

```
lab@rdma-b:~$ ib_send_lat -d rxe0 192.168.124.224
---------------------------------------------------------------------------------------
                    Send Latency Test
 Dual-port       : OFF          Device         : rxe0
 Number of qps   : 1            Transport type : IB
 Connection type : RC           Using SRQ      : OFF
 PCIe relax order: ON
 ibv_wr* API     : OFF
 TX depth        : 1
 Mtu             : 1024[B]
 Link type       : Ethernet
 GID index       : 1
 Max inline data : 0[B]
 rdma_cm QPs     : OFF
 Data ex. method : Ethernet
---------------------------------------------------------------------------------------
 local address: LID 0000 QPN 0x0013 PSN 0x2d2d36
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:192:168:124:208
 remote address: LID 0000 QPN 0x0014 PSN 0x3bbebe
 GID: 00:00:00:00:00:00:00:00:00:00:255:255:192:168:124:224
---------------------------------------------------------------------------------------
 #bytes #iterations    t_min[usec]    t_max[usec]  t_typical[usec]    t_avg[usec]    t_stdev[usec]   99% percentile[usec]   99.9% percentile[usec]
 2       1000          17.09          42.54        21.62               21.95            1.50    26.92            42.54
---------------------------------------------------------------------------------------
lab@rdma-b:~$
```