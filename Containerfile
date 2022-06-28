# /*******************************************************************************
#  * (c) Copyright IBM Corporation 2022.
#  *
#  * Licensed under the Apache License, Version 2.0 (the "License");
#  * you may not use this file except in compliance with the License.
#  * You may obtain a copy of the License at
#  *
#  *    https://www.apache.org/licenses/LICENSE-2.0
#  *
#  * Unless required by applicable law or agreed to in writing, software
#  * distributed under the License is distributed on an "AS IS" BASIS,
#  * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  * See the License for the specific language governing permissions and
#  * limitations under the License.
#  *******************************************************************************/
# 
# Building:
#   podman build --platform linux/amd64,linux/arm64,linux/ppc64le,linux/s390x --jobs=1 --manifest localhost/containerdiag:latest .
#   podman manifest inspect localhost/containerdiag:latest
#   podman login quay.io
#   podman manifest push --all localhost/containerdiag:latest docker://quay.io/ibm/containerdiag:latest
#   Check at https://quay.io/repository/ibm/containerdiag?tab=tags
# 
# Notes:
#   * As of writing this note, this image is about 1GB
#   * Base fedora:latest is about 175MB
#   * Tried ubi-minimal which is about 100MB but microdnf is missing many useful packages like fatrace and others 
#   * gdb adds about 68MB but considered worth it for gdb and gcore
#   * runc adds about 14MB but considered worth it for use with oc debug on a node
#   * git adds about 41MB so instead we just use wget https://github.com/$GROUP/$REPO/archive/master.zip
#   * perf adds about 40MB but considered worth it since it's commonly needed
#   * perl adds about 150MB but is needed for FlameGraph
#   * Then there is also a Java 11 JDK which is another few hundred MB
#   * Deleting files in the parent (e.g. /usr/lib64/python*/__pycache__) isn't useful because it's still in that layer

# podman manifest inspect docker.io/fedora:latest
FROM --platform=$TARGETPLATFORM docker.io/fedora:latest

# https://github.com/opencontainers/image-spec/blob/main/annotations.md#pre-defined-annotation-keys
LABEL org.opencontainers.image.title="containerdiag"
LABEL org.opencontainers.image.description="Live container debugging using worker node debug pods"
LABEL org.opencontainers.image.url="https://github.com/IBM/containerdiag"
LABEL org.opencontainers.image.source="https://github.com/IBM/containerdiag/blob/main/Containerfile"
LABEL org.opencontainers.image.authors="kevin.grigorenko@us.ibm.com"
LABEL org.opencontainers.image.licenses="Apache-2.0"

RUN dnf install -y \
        binutils \
        curl \
        fatrace \
        gawk \
        gdb \
        hostname \
        iproute \
        iputils \
        jq \
        less \
        lsof \
        ltrace \
        ncdu \
        net-tools \
        nmon \
        p7zip \
        perf \
        perl \
        procps-ng \
        psmisc \
        runc \
        sysstat \
        strace \
        tcpdump \
        telnet \
        traceroute \
        tree \
        unzip \
        util-linux \
        vim \
        wget \
        zip \
      && \
    dnf clean all && \
    rm -rf \
            /usr/share/vim/*/doc/ \
            /usr/share/vim/*/spell/ \
            /usr/share/vim/*/tutor/

RUN mkdir -p /opt/java/11/ && \
    wget -q -O - https://www.ibm.com/semeru-runtimes/api/v3/binary/latest/11/ga/linux/$(if [ "$(uname -m)" = "x86_64" ]; then echo "x64"; else uname -m; fi)/jdk/openj9/normal/ibm | tar -xzf - --directory /opt/ && \
    mv /opt/jdk* /opt/java/11/semeru && \
    for J in java javac jar jdmpview javap jcmd jpackcore keytool jstat jdb jps jstack jconsole jjs jmap jrunscript jitserver jshell traceformat; do \
      ln -s /opt/java/11/semeru/bin/${J} /usr/local/bin/; \
    done

RUN get_git() { \
      wget -q -O /tmp/$1_$2_master.zip https://github.com/$1/$2/archive/master.zip; \
      unzip -q /tmp/$1_$2_master.zip -d /opt/; \
      mv /opt/$2-master /opt/$2/; \
      rm /tmp/$1_$2_master.zip; \
    } && \
    get_git brendangregg FlameGraph && \
    ln -s /opt/FlameGraph/stackcollapse-perf.pl /usr/local/bin/ && \
    ln -s /opt/FlameGraph/flamegraph.pl /usr/local/bin/ && \
    get_git kgibm problemdetermination && \
    ln -s /opt/problemdetermination/scripts/java/j9/j9javacores.awk /usr/local/bin/ && \
    ln -s /opt/problemdetermination/scripts/ihs/ihs_mpmstats.awk /usr/local/bin/ && \
    ln -s /opt/problemdetermination/scripts/was/twas_pmi_threadpool.awk /usr/local/bin/

COPY scripts/*.sh scripts/*.awk /opt/

RUN for SCRIPT in /opt/*.sh /opt/*.awk; do \
      chmod a+x ${SCRIPT}; \
      ln -s ${SCRIPT} /usr/local/bin/; \
    done

# Defer to the ENTRYPOINT/CMD of Fedora which is bash
