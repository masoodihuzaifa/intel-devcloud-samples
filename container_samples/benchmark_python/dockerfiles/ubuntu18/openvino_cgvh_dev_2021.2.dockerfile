# Copyright (C) 2019-2021 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
FROM ubuntu:18.04 AS base

# hadolint ignore=DL3002
USER root
WORKDIR /

SHELL ["/bin/bash", "-xo", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends curl tzdata ca-certificates && \
    rm -rf /var/lib/apt/lists/*




RUN echo "Installing OpenVINO ......."
# download source for pypi-kenlm LGPL package
WORKDIR /tmp
RUN curl -L https://files.pythonhosted.org/packages/7f/e6/1639d2de28c27632e3136015ecfd67774cca6f55146507baeaef06b113ba/pypi-kenlm-0.1.20190403.tar.gz --output pypi-kenlm.tar.gz


# get product from URL
ARG package_url
ARG TEMP_DIR=/tmp/openvino_installer

WORKDIR ${TEMP_DIR}
# hadolint ignore=DL3020
ADD ${package_url} ${TEMP_DIR}

# install product by copying archive content
ARG TEMP_DIR=/tmp/openvino_installer
ENV INTEL_OPENVINO_DIR /opt/intel/openvino

RUN tar -xzf "${TEMP_DIR}"/*.tgz && \
    OV_BUILD="$(find . -maxdepth 1 -type d -name "*openvino*" | grep -oP '(?<=_)\d+.\d+.\d+')" && \
    OV_YEAR="$(find . -maxdepth 1 -type d -name "*openvino*" | grep -oP '(?<=_)\d+')" && \
    OV_FOLDER="$(find . -maxdepth 1 -type d -name "*openvino*")" && \
    mkdir -p /opt/intel/openvino_"$OV_BUILD"/ && \
    cp -rf "$OV_FOLDER"/*  /opt/intel/openvino_"$OV_BUILD"/ && \
    rm -rf "${TEMP_DIR:?}"/"$OV_FOLDER" && \
    ln --symbolic /opt/intel/openvino_"$OV_BUILD"/ /opt/intel/openvino && \
    ln --symbolic /opt/intel/openvino_"$OV_BUILD"/ /opt/intel/openvino_"$OV_YEAR" && \
    rm -rf ${INTEL_OPENVINO_DIR}/deployment_tools/tools/workbench && rm -rf ${TEMP_DIR}



# for GPU
ARG GMMLIB
ARG IGC_CORE
ARG IGC_OPENCL
ARG INTEL_OPENCL
ARG INTEL_OCLOC
ARG TEMP_DIR=/tmp/opencl

WORKDIR ${TEMP_DIR}
RUN curl -L "https://github.com/intel/compute-runtime/releases/download/${INTEL_OPENCL}/intel-gmmlib_${GMMLIB}_amd64.deb" --output "intel-gmmlib_${GMMLIB}_amd64.deb" && \
    curl -L "https://github.com/intel/compute-runtime/releases/download/${INTEL_OPENCL}/intel-igc-core_${IGC_CORE}_amd64.deb" --output "intel-igc-core_${IGC_CORE}_amd64.deb" && \
    curl -L "https://github.com/intel/compute-runtime/releases/download/${INTEL_OPENCL}/intel-igc-opencl_${IGC_OPENCL}_amd64.deb" --output "intel-igc-opencl_${IGC_OPENCL}_amd64.deb" && \
    curl -L "https://github.com/intel/compute-runtime/releases/download/${INTEL_OPENCL}/intel-opencl_${INTEL_OPENCL}_amd64.deb" --output "intel-opencl_${INTEL_OPENCL}_amd64.deb" && \
    curl -L "https://github.com/intel/compute-runtime/releases/download/${INTEL_OPENCL}/intel-ocloc_${INTEL_OCLOC}_amd64.deb" --output "intel-ocloc_${INTEL_OCLOC}_amd64.deb"


# for VPU
ARG BUILD_DEPENDENCIES="autoconf \
                        automake \
                        build-essential \
                        libtool \
                        unzip"

# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends ${BUILD_DEPENDENCIES} && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN curl -L https://github.com/libusb/libusb/archive/v1.0.22.zip --output v1.0.22.zip && \
    unzip v1.0.22.zip && rm -rf v1.0.22.zip

WORKDIR /opt/libusb-1.0.22
RUN ./bootstrap.sh && \
    ./configure --disable-udev --enable-shared && \
    make -j4

# -----------------
FROM ubuntu:18.04 AS ov_base

LABEL Description="This is the dev image for Intel(R) Distribution of OpenVINO(TM) toolkit on Ubuntu 18.04 LTS"
LABEL Vendor="Intel Corporation"

USER root
WORKDIR /

SHELL ["/bin/bash", "-xo", "pipefail", "-c"]

# Creating user openvino and adding it to groups "video" and "users" to use GPU and VPU
RUN useradd -ms /bin/bash -G video,users openvino && \
    chown openvino -R /home/openvino

RUN mkdir /opt/intel

ENV INTEL_OPENVINO_DIR /opt/intel/openvino

COPY --from=base /opt/intel /opt/intel

WORKDIR /thirdparty


ARG DEPS=dpkg-dev
ARG LGPL_DEPS="g++ \
               gcc \
               libc6-dev \
               libgtk-3-0"


ARG INSTALL_SOURCES="no"

# hadolint ignore=DL3008
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends curl tzdata && \
    apt-get install -y --no-install-recommends ${DEPS} && \
    dpkg --get-selections | grep -v deinstall | awk '{print $1}' > base_packages.txt  && \
    rm -rf /var/lib/apt/lists/*

# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends ${LGPL_DEPS} && \
    if [ "$INSTALL_SOURCES" = "yes" ]; then \
      sed -Ei 's/# deb-src /deb-src /' /etc/apt/sources.list && \
      apt-get update && \
	  dpkg --get-selections | grep -v deinstall | awk '{print $1}' > all_packages.txt && \
	  grep -v -f base_packages.txt all_packages.txt | while read line; do \
	  package=`echo $line`; \
	  name=(${package//:/ }); \
      grep -l GPL /usr/share/doc/${name[0]}/copyright; \
      exit_status=$?; \
	  if [ $exit_status -eq 0 ]; then \
	    apt-get source -q --download-only $package;  \
	  fi \
      done && \
      echo "Download source for `ls | wc -l` third-party packages: `du -sh`"; fi && \
    rm -rf /var/lib/apt/lists/* && rm -rf *.txt


# setup Python
ENV PYTHON_VER python3.6


RUN apt-get update && \
    apt-get install -y --no-install-recommends vim  && \
    rm -rf /var/lib/apt/lists/*

# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3-pip python3-dev python3-venv python3-setuptools lib${PYTHON_VER} && \
    rm -rf /var/lib/apt/lists/*


RUN ${PYTHON_VER} -m pip install --upgrade pip

# dev package
WORKDIR /tmp

RUN ${PYTHON_VER} -m pip install --no-cache-dir cmake && \
    ${PYTHON_VER} -m pip install --no-cache-dir -r ${INTEL_OPENVINO_DIR}/python/${PYTHON_VER}/requirements.txt && \
    find "${INTEL_OPENVINO_DIR}/" -type f \( -name "*requirements.*" -o  -name "*requirements_ubuntu18.*" -o \( -name "*requirements*.in" -and -not -name "*requirements-tensorflow.in" \) \) -not -path "*/accuracy_checker/*" -not -path "*/post_training_optimization_toolkit/*" -not -path "*/python3*/*" -not -path "*/python2*/*" -print -exec ${PYTHON_VER} -m pip install --no-cache-dir -r "{}" \;

ENV VENV_TF2 /opt/intel/venv_tf2

RUN ${PYTHON_VER} -m venv ${VENV_TF2} && \
    source ${VENV_TF2}/bin/activate && \
    pip install --no-cache-dir -U pip==19.3.1 && \
    find "${INTEL_OPENVINO_DIR}/deployment_tools/model_optimizer/" -type f \( -name "*requirements*.txt" -and -not -name "*requirements_tf.txt" \) -print -exec ${PYTHON_VER} -m pip install --no-cache-dir -r "{}" \; && \
    find "${INTEL_OPENVINO_DIR}/deployment_tools/open_model_zoo/tools/downloader/" -type f -name "*requirements*.in" -print -exec ${PYTHON_VER} -m pip install --no-cache-dir -r "{}" \; && \
    deactivate


WORKDIR ${INTEL_OPENVINO_DIR}/deployment_tools/open_model_zoo/tools/accuracy_checker
RUN source ${INTEL_OPENVINO_DIR}/bin/setupvars.sh && \
    ${PYTHON_VER} -m pip install --no-cache-dir -r ${INTEL_OPENVINO_DIR}/deployment_tools/open_model_zoo/tools/accuracy_checker/requirements.in && \
    ${PYTHON_VER} ${INTEL_OPENVINO_DIR}/deployment_tools/open_model_zoo/tools/accuracy_checker/setup.py install && \
    rm -rf ${INTEL_OPENVINO_DIR}/deployment_tools/open_model_zoo/tools/accuracy_checker/build

# download source for pypi-kenlm LGPL package
COPY --from=base /tmp/pypi-kenlm.tar.gz /thirdparty/pypi-kenlm.tar.gz

WORKDIR ${INTEL_OPENVINO_DIR}/deployment_tools/tools/post_training_optimization_toolkit
RUN ${PYTHON_VER} -m pip install --no-cache-dir -r ${INTEL_OPENVINO_DIR}/deployment_tools/tools/post_training_optimization_toolkit/requirements.txt && \
    ${PYTHON_VER} ${INTEL_OPENVINO_DIR}/deployment_tools/tools/post_training_optimization_toolkit/setup.py install && \
    rm -rf ${INTEL_OPENVINO_DIR}/deployment_tools/tools/post_training_optimization_toolkit/build

# for CPU

# for GPU
ARG TEMP_DIR=/tmp/opencl

COPY --from=base ${TEMP_DIR} ${TEMP_DIR}

WORKDIR ${TEMP_DIR}
# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends ocl-icd-libopencl1 && \
    rm -rf /var/lib/apt/lists/* && \
    dpkg -i ${TEMP_DIR}/*.deb && \
    ldconfig && \
    rm -rf ${TEMP_DIR}

# for VPU
ARG LGPL_DEPS=udev

WORKDIR /thirdparty

# hadolint ignore=DL3008
RUN apt-get update && \
    dpkg --get-selections | grep -v deinstall | awk '{print $1}' > no_vpu_packages.txt && \
    apt-get install -y --no-install-recommends ${LGPL_DEPS} && \
    if [ "$INSTALL_SOURCES" = "yes" ]; then \
      sed -Ei 's/# deb-src /deb-src /' /etc/apt/sources.list && \
      apt-get update && \
	  dpkg --get-selections | grep -v deinstall | awk '{print $1}' > vpu_packages.txt && \
	  grep -v -f no_vpu_packages.txt vpu_packages.txt | while read line; do \
	  package=`echo $line`; \
	  name=(${package//:/ }); \
      grep -l GPL /usr/share/doc/${name[0]}/copyright; \
      exit_status=$?; \
	  if [ $exit_status -eq 0 ]; then \
	    apt-get source -q --download-only $package;  \
	  fi \
      done && \
      echo "Download source for `ls | wc -l` third-party packages: `du -sh`"; fi && \
    rm -rf /var/lib/apt/lists/* && rm -rf *.txt

COPY --from=base /opt/libusb-1.0.22 /opt/libusb-1.0.22

WORKDIR /opt/libusb-1.0.22/libusb
RUN /bin/mkdir -p '/usr/local/lib' && \
    /bin/bash ../libtool   --mode=install /usr/bin/install -c   libusb-1.0.la '/usr/local/lib' && \
    /bin/mkdir -p '/usr/local/include/libusb-1.0' && \
    /usr/bin/install -c -m 644 libusb.h '/usr/local/include/libusb-1.0' && \
    /bin/mkdir -p '/usr/local/lib/pkgconfig'

WORKDIR /opt/libusb-1.0.22/
RUN /usr/bin/install -c -m 644 libusb-1.0.pc '/usr/local/lib/pkgconfig' && \
    cp ${INTEL_OPENVINO_DIR}/deployment_tools/inference_engine/external/97-myriad-usbboot.rules /etc/udev/rules.d/ && \
    ldconfig

# for HDDL
WORKDIR /tmp
# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libboost-filesystem1.65-dev \
        libboost-thread1.65-dev \
        libjson-c3 libxxf86vm-dev && \
    rm -rf /var/lib/apt/lists/* && rm -rf /tmp/*


# Post-installation cleanup and setting up OpenVINO environment variables
RUN if [ -f "${INTEL_OPENVINO_DIR}"/bin/setupvars.sh ]; then \
        printf "\nexport TBB_DIR=\${INTEL_OPENVINO_DIR}/deployment_tools/inference_engine/external/tbb/cmake\n" >> ${INTEL_OPENVINO_DIR}/bin/setupvars.sh; \
        printf "\nsource \${INTEL_OPENVINO_DIR}/bin/setupvars.sh\n" >> /home/openvino/.bashrc; \
        printf "\nsource \${INTEL_OPENVINO_DIR}/bin/setupvars.sh\n" >> /root/.bashrc; \
    fi; \
    if [ -d "${INTEL_OPENVINO_DIR}"/opt/intel/mediasdk ]; then \
        printf "\nexport LIBVA_DRIVER_NAME=iHD \nexport LIBVA_DRIVERS_PATH=\${INTEL_OPENVINO_DIR}/opt/intel/mediasdk/lib64/ \nexport GST_VAAPI_ALL_DRIVERS=1 \nexport LIBRARY_PATH=\${INTEL_OPENVINO_DIR}/opt/intel/mediasdk/lib64/:\$LIBRARY_PATH \nexport LD_LIBRARY_PATH=\${INTEL_OPENVINO_DIR}/opt/intel/mediasdk/lib64/:\$LD_LIBRARY_PATH \n" >> /home/openvino/.bashrc; \
        printf "\nexport LIBVA_DRIVER_NAME=iHD \nexport LIBVA_DRIVERS_PATH=\${INTEL_OPENVINO_DIR}/opt/intel/mediasdk/lib64/ \nexport GST_VAAPI_ALL_DRIVERS=1 \nexport LIBRARY_PATH=\${INTEL_OPENVINO_DIR}/opt/intel/mediasdk/lib64/:\$LIBRARY_PATH \nexport LD_LIBRARY_PATH=\${INTEL_OPENVINO_DIR}/opt/intel/mediasdk/lib64/:\$LD_LIBRARY_PATH \n" >> /root/.bashrc; \
    fi;


RUN echo "OpenVINO installation done  ......."
RUN echo "Intel devcloud Sample containerization begin ......."
USER root
RUN apt-get  -y update
RUN apt-get install ffmpeg libsm6 libxext6 -y 
RUN chmod 0777 ${INTEL_OPENVINO_DIR}/python
RUN mkdir -p  ${INTEL_OPENVINO_DIR}/python/samples
RUN chmod 777   ${INTEL_OPENVINO_DIR}/python/samples

ADD third-party-utils/Anaconda3-2019.03-Linux-x86_64.sh ${INTEL_OPENVINO_DIR}/python/samples/ 
RUN chmod 0755 ${INTEL_OPENVINO_DIR}/python/samples/Anaconda3-2019.03-Linux-x86_64.sh
RUN bash ${INTEL_OPENVINO_DIR}/python/samples/Anaconda3-2019.03-Linux-x86_64.sh -b && \ 
    echo "export PATH="/root/anaconda3/bin:$PATH"" >> ~/.bashrc && \
    /bin/bash -c "source ~/.bashrc"

RUN chmod 777 /opt/intel/openvino_2021.2.185/deployment_tools/model_optimizer/install_prerequisites/install_prerequisites_caffe.sh 
RUN chmod 777 /opt/intel/openvino_2021.2.185/deployment_tools/model_optimizer/install_prerequisites/install_prerequisites.sh 

RUN apt-get update && \
    apt-get autoremove -y dpkg-dev && \
    rm -rf /var/lib/apt/lists/*
 

RUN groupadd intel

ENV USERNAME=intel
ENV PASSWORD=intel

RUN useradd -m -p $(openssl passwd -1 ${PASSWORD}) -s /bin/bash -g sudo ${USERNAME}
RUN usermod -a -G  intel  intel

RUN mkdir -p  ${INTEL_OPENVINO_DIR}/python/samples

ADD benchmark_python ${INTEL_OPENVINO_DIR}/python/samples/benchmark_python
COPY benchmark_python/main.py /opt/intel/openvino_2021.2.185/python/python3.7/openvino/tools/benchmark/main.py
COPY benchmark_python/main.py /opt/intel/openvino_2021.2.185/python/python3.6/openvino/tools/benchmark/main.py
COPY benchmark_python/main.py /opt/intel/openvino_2021.2.185/python/python3.6/openvino/tools/benchmark/main.py
COPY benchmark_python/run_benchmark.sh ${INTEL_OPENVINO_DIR}/python/samples/benchmark_python
COPY benchmark_python/benchmark.sh ${INTEL_OPENVINO_DIR}/python/samples/benchmark_python
RUN chown -R  intel:intel  ${INTEL_OPENVINO_DIR} ${INTEL_OPENVINO_DIR}/python  ${INTEL_OPENVINO_DIR}/python/samples  ${INTEL_OPENVINO_DIR}/deployment_tools ${INTEL_OPENVINO_DIR}/deployment_tools/model_optimizer ${INTEL_OPENVINO_DIR}/deployment_tools/model_optimizer/install_prerequisites  /var/lib/dpkg ${INTEL_OPENVINO_DIR}/python/samples/benchmark_python

RUN chmod 777 ${INTEL_OPENVINO_DIR}/deployment_tools/model_optimizer/mo.py
RUN chmod 777 ${INTEL_OPENVINO_DIR}/python/samples
RUN chmod 777 ${INTEL_OPENVINO_DIR}/python/samples/benchmark_python/*.sh
RUN apt-get install ffmpeg libsm6 libxext6 -y 

USER intel


RUN bash ${INTEL_OPENVINO_DIR}/python/samples/Anaconda3-2019.03-Linux-x86_64.sh -b 
    
    
#Set path to conda
ENV PATH /home/intel/anaconda3/bin:$PATH
RUN pip install --no-cache jupyterhub
RUN pip install notebook
RUN pip install tensorflow==1.15.2  
RUN conda install -c conda-forge configurable-http-proxy
RUN conda install -c conda-forge ruamel.yaml
RUN conda search python
ENV PATH ${INTEL_OPENVINO_DIR}/python/samples:$PATH


ADD third-party-utils/qarpo  ${INTEL_OPENVINO_DIR}/python/samples/qarpo
ADD third-party-utils/application_metrics_writer-0.1-py2.py3-none-any.whl ${INTEL_OPENVINO_DIR}/python/samples/
RUN openssl rand -hex 32 > jupyterhub_cookie_secret

ARG DEVICE="CPU"
ENV DEVICE=$device 
 
RUN pip install ${INTEL_OPENVINO_DIR}/python/samples/qarpo/qarpo-1.0.30-py3-none-any.whl
RUN pip install ${INTEL_OPENVINO_DIR}/python/samples/qarpo/application_metrics_writer-0.1-py2.py3-none-any.whl
RUN pip install --upgrade protobuf==3.6.1
RUN pip install test-generator==0.1.1
RUN conda install -c menpo opencv
RUN source  /opt/intel/openvino_2021.2.185/bin/setupvars.sh 

RUN echo "Generating OpenVINO IR files ......."
RUN echo "Executing benchmark app using OpenVINO ......."
WORKDIR ${INTEL_OPENVINO_DIR}/python/samples/benchmark_python 
#RUN /bin/bash -c "source ${INTEL_OPENVINO_DIR}/python/samples/benchmark_python/benchmark.sh"
ENTRYPOINT  ${INTEL_OPENVINO_DIR}/python/samples/benchmark_python/benchmark.sh
