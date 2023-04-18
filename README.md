# containerdiag

This repository builds a container image available at [quay.io/ibm/containerdiag](https://quay.io/repository/ibm/containerdiag?tab=tags) that helps perform diagnostics on running containers using [worker node debug pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/#node-shell-session). This requires cluster administrator privileges. For additional details, see <https://www.ibm.com/support/pages/mustgather-performance-hang-or-high-cpu-issues-websphere-application-server-linux-containers>

## Motivation

The main issue today in remoting into running containers and debugging them is that you are limited to the diagnostic tools baked into the container image (until [ephemeral debug containers](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/#ephemeral-container) become more widely available, although they may have some limits). A general best practice is to build images with minimal utilities, so administrators are often lacking even basic tools like `top -H`, `pstack`, `netstat`, etc.

This `containerdiag` image may be used to run a worker node debug pod with the diagnostic tools that you want. This image contains commonly used diagnostic tools and shell scripts that help perform key functions such as mapping a pod name to a worker node process ID to target diagnostic tools at it or getting its ephemeral filesystem to gather files from the container. For example, to get per-thread CPU usage for 10 seconds given a pod name and then gather the `/logs` directory:

`oc debug node/$NODE -t --image=quay.io/ibm/containerdiag -- run.sh sh -c 'top -b -H -d 2 -n 5 -p $(podinfo.sh -p $POD) > top.txt && podfscp.sh -s -p $POD /logs'`

## Examples

For additional details, see <https://www.ibm.com/support/pages/mustgather-performance-hang-or-high-cpu-issues-websphere-application-server-linux-containers>

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

## Development

### Steps to publish a new image to Quay

1. On macOS using `podman`, for the first time using a `podman machine`, install `qemu-user-static` for cross-compilation:
   ```
   podman machine ssh "sudo rpm-ostree install qemu-user-static; sudo systemctl reboot"
   ```
1. Create the manifest (error if it exists is okay):
   ```
   podman manifest create quay.io/ibm/containerdiag:latest
   ```
1. Remove any existing manifest images:
   ```
   for i in $(podman manifest inspect quay.io/ibm/containerdiag:latest | jq '.manifests[].digest' | tr '\n' ' ' | sed 's/"//g'); do podman manifest remove quay.io/ibm/containerdiag:latest $i; done
   ```
1. Check that the manifest has no images:
   ```
   podman manifest inspect quay.io/ibm/containerdiag:latest
   ```
1. Build the images:
   ```
   podman build --platform linux/amd64,linux/ppc64le,linux/s390x,linux/arm64 --jobs=1 --manifest quay.io/ibm/containerdiag:latest .
   ```
1. Check that the manifest looks good:
   ```
   podman manifest inspect quay.io/ibm/containerdiag:latest
   ```
1. Log into Quay:
   ```
   podman login quay.io
   ```
1. If testing is needed:
    1. The debug node command pulls `:latest`, so to test under a different tag, make the tag unique, e.g.:
       ```
       podman manifest push --all quay.io/ibm/containerdiag:latest docker://quay.io/ibm/containerdiag:test$(date +%Y%m%d)
       ```
    1. Then test with that image, for examples:
       ```
       ./containerdiag.sh -i quay.io/ibm/containerdiag:test$(date +%Y%m%d) -d $DEPLOYMENT -n $NAMESPACE test.sh
       ./containerdiag.sh -i quay.io/ibm/containerdiag:test$(date +%Y%m%d) -p $POD -n $NAMESPACE run.sh sh -c 'top -b -d 1 -n 1 > top.txt'
       ./containerdiag.sh -i quay.io/ibm/containerdiag:test$(date +%Y%m%d) -p $POD -n $NAMESPACE libertyperf.sh -s 60
       ```
    1. Delete the test tag from <https://quay.io/repository/ibm/containerdiag?tab=tags>
1. Push to the latest tag:
   ```
   podman manifest push --all quay.io/ibm/containerdiag:latest docker://quay.io/ibm/containerdiag:latest
   ```

### Steps to publish new builds of containerdiag.sh and/or containerdiag.bat

1. Update the date in the `VERSION` variable at the top of the script(s)
1. `git commit -a -s -S -m "$DESCRIPTION"`
1. `git push`
1. `git tag 0.1.$(date +%Y%m%d)`
1. `git push --tags`
1. Wait for the [release action](https://github.com/IBM/containerdiag/actions) to complete and find the download links at <https://github.com/IBM/containerdiag/releases/latest>
1. Update <https://www.ibm.com/support/pages/mustgather-performance-hang-or-high-cpu-issues-websphere-application-server-linux-containers>
    1. Update the link to `containerdiag.sh` and `containerdiag.bat` to include the tag name
    1. Update the revision history
