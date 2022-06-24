#Copyright (C) 2022 Intel Corporation
#SPDX-License-Identifier: MIT

#Building openvino base image from public source

FROM openvino/ubuntu18_dev:2022.1.0
RUN pip install openvino-dev[caffe]


RUN echo "OpenVINO installation done  ......."
RUN echo "Intel devcloud Sample containerization begin ......."

USER root

RUN apt-get update && \
    apt-get autoremove -y dpkg-dev && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p  ${INTEL_OPENVINO_DIR}/python/samples

ADD developer-samples/python/pneumonia-classification  ${INTEL_OPENVINO_DIR}/python/samples/pneumonia-classification


RUN chmod -R 777 ${INTEL_OPENVINO_DIR}/python/samples/
RUN chmod 777 ${INTEL_OPENVINO_DIR}/python/samples/pneumonia-classification/*.sh


ARG DEVICE="CPU"
ENV DEVICE=$DEVICE

ARG PRECISION="FP16"
ENV PRECISION="$PRECISION"

ARG OPENVINO_VERSION="2022.1.0.643"
ENV OPENVINO_VERSION=$OPENVINO_VERSION

ARG RUN_ON_PREM="/mount_folder"
ENV RUN_ON_PREM=$RUN_ON_PREM

ARG OUTPUT_FOLDER="output_pneumnia_classification"
ENV OUTPUT_FOLDER=$OUTPUT_FOLDER


ARG SUPPORTED_HW="CPU_TDP_70_205W"
ENV SUPPORTED_HW=$SUPPORTED_HW

RUN source  /opt/intel/openvino_$OPENVINO_VERSION/setupvars.sh


RUN echo "Generating OpenVINO IR files ......."
RUN echo "Executing object detection app using OpenVINO ......."
WORKDIR ${INTEL_OPENVINO_DIR}/python/samples/pneumonia-classification
ENTRYPOINT /bin/bash -c "source ${INTEL_OPENVINO_DIR}/python/samples/pneumonia-classification/run_pneumonia.sh"

