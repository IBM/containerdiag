# containerdiag

This container image, available at [quay.io/ibm/containerdiag](https://quay.io/repository/ibm/containerdiag?tab=tags), helps perform diagnostics on running containers using [worker node debug pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/#node-shell-session). This requires cluster administrator privileges and runs the debug pod as `root`.

The main issue today in remoting into running containers and debugging them is that you are limited to the diagnostic tools baked into the container image (until [ephemeral debug containers](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/#ephemeral-container) become more widely available). A general best practice is to build images with minimal utilities, so administrators are often lacking even basic tools like `top -H` to investigate per-thread CPU utilization.

One option is to run a worker node debug pod using an image that has the diagnostic tools that you want. This `containerdiag` image provides commonly used diagnostic tools and shell scripts that help perform key functions such as mapping a pod name to a worker node process ID to target diagnostic tools at it or getting its ephemeral filesystem to gather files from the container. For example, to get per-thread CPU usage for 10 seconds given a pod name and then gather the `/logs` directory:

`oc debug node/$NODE -t --image=quay.io/ibm/containerdiag -- run.sh sh -c 'top -b -H -d 2 -n 5 -p $(podinfo.sh -p $POD) > top.txt && podfscp.sh -s -p $POD /logs'`

## Examples

### WebSphere Liberty performance, hang, or high CPU issues

Execute the [WebSphere Performance, hang, or high CPU issues MustGather](https://www.ibm.com/support/pages/mustgather-performance-hang-or-high-cpu-issues-websphere-application-server-linux), execute [`server dump`](https://www.ibm.com/docs/en/was-liberty/core?topic=line-generating-liberty-server-dump-from-command), gather Liberty logs, configuration, the MustGather output, javacores, and any server dumps, and finally delete the javacores and any server dumps.

Replace `$NODE` with the node name and `$PODS` with the pod names (space-delimited):

```
oc debug node/$NODE -t --image=quay.io/ibm/containerdiag -- libertyperf.sh $PODS
```

### WebSphere Application Server traditional Base performance, hang, or high CPU issues

Execute the [WebSphere Performance, hang, or high CPU issues MustGather](https://www.ibm.com/support/pages/mustgather-performance-hang-or-high-cpu-issues-websphere-application-server-linux), gather WAS traditional logs, configuration, the MustGather output, and javacores, and finally delete the javacores.

Replace `$NODE` with the node name and `$PODS` with the pod names (space-delimited):

```
oc debug node/$NODE -t --image=quay.io/ibm/containerdiag -- twasperf.sh $PODS
```

### tcpdump

Execute [`tcpdump`](https://www.kernel.org/doc/man-pages/online/pages/man1/tcpdump.1.html) for a specified duration. Replace `$DURATION` with a time in seconds:

```
oc debug node/$NODE -t --image=quay.io/ibm/containerdiag -- tcpdump.sh -0 $DURATION
```

### perf

Execute [`perf`](https://www.kernel.org/doc/man-pages/online/pages/man1/perf.1.html) for a specified duration. Replace `$DURATION` with a time in seconds:

```
oc debug node/$NODE -t --image=quay.io/ibm/containerdiag -- perf.sh -d $DURATION
```

## Support

This image is provided as is without any warranty or support but we will do our best to respond to issues as time permits.
