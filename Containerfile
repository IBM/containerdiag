# /*******************************************************************************
#  * (c) Copyright IBM Corporation 2023.
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
# Live container debugging using worker node debug pods
#
# Notes:
#   * View tags at https://quay.io/repository/ibm/containerdiag?tab=tags
#   * As of writing this note, this image is about 1.5GB
#       * Base fedora:latest is about 175MB
#       * Tried ubi-minimal which is about 100MB but microdnf is missing many useful packages like fatrace and others 
#       * gdb adds about 68MB but considered worth it for gdb and gcore
#       * runc adds about 14MB but considered worth it for use with oc debug on a node
#       * git adds about 41MB so instead we just use wget https://github.com/$GROUP/$REPO/archive/master.zip
#       * perf adds about 40MB but considered worth it since it's commonly needed
#       * perl adds about 150MB but is needed for FlameGraph
#       * Then there is also a Java JDK which is another few hundred MB
#       * The oc command is about 120MB
#       * Deleting files in the parent (e.g. /usr/lib64/python*/__pycache__) isn't useful because it's still in that layer
#   * See available architectures for Fedora: podman manifest inspect docker.io/fedora:latest

FROM docker.io/fedora:latest

ARG TITLE="containerdiag"
ARG DESCRIPTION="Live container debugging using worker node debug pods"
ARG AUTHORS="kevin.grigorenko@us.ibm.com"
# https://spdx.org/licenses/
ARG LICENSE="Apache-2.0"
ARG URL="https://github.com/IBM/containerdiag"
ARG SOURCE="https://github.com/IBM/containerdiag/blob/main/Containerfile"
ARG JAVA_VERSION="17"

# https://github.com/opencontainers/image-spec/blob/main/annotations.md#pre-defined-annotation-keys
LABEL org.opencontainers.image.title="${TITLE}" \
      name="${TITLE}" \
      org.opencontainers.image.description="${DESCRIPTION}" \
      description="${DESCRIPTION}" \
      org.opencontainers.image.url="${URL}" \
      org.opencontainers.image.source="${SOURCE}" \
      org.opencontainers.image.authors="${AUTHORS}" \
      org.opencontainers.image.licenses="${LICENSE}" \
      license="${LICENSE}"

# Install various tools
RUN dnf install -y \
        binutils \
        containerd \
        coreutils \
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

# Install oc. We delete kubectl because the README notes:
#   > The `kubectl` binary is included alongside for when strict Kubernetes compliance is necessary.
# We don't expect our users will need such strict compliance and it saves over 100MB
# Then we symlink oc to kubectl in case someone uses that command by habit
RUN mkdir -p /opt/openshift/ && \
    wget -q -O - https://mirror.openshift.com/pub/openshift-v4/$(uname -m)/clients/ocp/latest/openshift-client-linux.tar.gz | tar -xzf - --directory /opt/openshift/ && \
    rm /opt/openshift/kubectl && \
    ln -s /opt/openshift/oc /opt/openshift/kubectl && \
    ln -s /opt/openshift/oc /usr/local/bin/ && \
    ln -s /opt/openshift/kubectl /usr/local/bin/

# Install Semeru Java
RUN mkdir -p /opt/java/${JAVA_VERSION}/ && \
    wget -q -O - https://www.ibm.com/semeru-runtimes/api/v3/binary/latest/${JAVA_VERSION}/ga/linux/$(if [ "$(uname -m)" = "x86_64" ]; then echo "x64"; else uname -m; fi)/jdk/openj9/normal/ibm | tar -xzf - --directory /opt/ && \
    mv /opt/jdk* /opt/java/${JAVA_VERSION}/semeru && \
    for J in java javac jar jdmpview javap jcmd jpackcore keytool jstat jdb jps jstack jconsole jjs jmap jrunscript jitserver jshell traceformat; do \
      ln -s /opt/java/${JAVA_VERSION}/semeru/bin/${J} /usr/local/bin/; \
    done

# Download a few useful git repositories like FlameGraph for Linux perf
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
    ln -s /opt/problemdetermination/scripts/was/twas_pmi_threadpool.awk /usr/local/bin/ && \
    get_git iovisor bcc

# Copy in our various helper scripts and put them on the $PATH
COPY scripts/*.sh /opt/
RUN for SCRIPT in /opt/*.sh; do \
      chmod a+x ${SCRIPT}; \
      ln -s ${SCRIPT} /usr/local/bin/; \
    done

RUN printf "Built: %s\n%s\n" "$(date)" "$(uname -a)" > /opt/containerdiag_buildinfo.txt

# Defer to the ENTRYPOINT/CMD of Fedora which is bash
