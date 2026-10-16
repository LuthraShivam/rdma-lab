# RDMA

Enables direct memory-to-memory data transfers between servers, bypassing CPU involvement.

## RDMA Architecture 

### Infiniband
InfiniBand (IB) is a high-speed, low latency, low CPU overhead, highly efficient and scalable server and storage interconnect technology.

InfiniBand uses I/O channels for data communication (up to 16 million per host), where each channel provides the semantics of a virtualized NIC or HCA (security, isolations, etc).

### Virtual Protocol Interconnect® (VPI)
For network adapters and switches supporting both infiniband and ethernet semantics.

Mix of both - check online for more details.

### RoCE (RDMA over Converged Ethernet)
RoCE (RDMA over Converged Ethernet) extends RDMA functionality to lossless Ethernet networks, delivering high-throughput, ultra-low latency communication.

RoCE provides true RDMA semantics for Ethernet as it does not require the complex and low performance TCP transport - low CPU overhead and takes advantage of Priority Flow Control in Data Center Bridging Ethernet for lossless connectivity.

Note: Ethernet iWARP, which is another RDMA tech, required TCP, although RoCE is much better than iWARP.

If you want to access memory from remote servers, you can use RDMA on top of iSCSI or SCSI protocols (others also available) to access that data - RDMA uses **Channel based IO** to achieve this.

**The most important point is that every application has direct access to the virtual memory of devices in the fabric. This means that applications do not need to make requests to an operating system to transfer messages.**

## Key components
1. Host Channel Adapter
2. Range Extenders
3. Subnet manager
4. Switches
5. Support for existing applications and ULPs

#### ULPs:
1. IPoIB - IP over InfiniBand
2. MPI - Message Passing Interface
3. NCCL - NVIDIA Collective Communication Library
4. SRP - SCSI RDMA Protocol
5. iSER - iSCSI Extensions for RDMA
6. RDS - Reliable Datagram Sockets

