FROM continuumio/miniconda3:24.7.1-0 AS build

ARG CUDA_VERSION=12.8.1
ENV CUDA_VERSION=$CUDA_VERSION

ARG PYTHON_VERSION=3.11.11
ENV PYTHON_VERSION=$PYTHON_VERSION

SHELL ["/bin/bash", "-l", "-c"]
ENV SHELL=/bin/bash
ENV HOST=0.0.0.0
ENV DEBIAN_FRONTEND=noninteractive
ENV CUDA_DOCKER_ARCH=all
ENV NVIDIA_VISIBLE_DEVICES=all
ENV CONDA_AUTO_UPDATE_CONDA="false"

ENV ALLTALK_DIR=/home/alltalk

##############################################################################
# Installation/Basic Utilities
##############################################################################
RUN <<EOR
    apt-get update
    apt-get upgrade -y
    apt-get install --no-install-recommends -y \
      espeak-ng \
      cron \
      curl \
      wget \
      jq \
      vim

    apt-get clean && rm -rf /var/lib/apt/lists/*
EOR

# Create a non-root user and switch to it for security
RUN useradd -ms /bin/bash alltalk
USER alltalk

##############################################################################
# Create a conda environment and install dependencies:
##############################################################################
RUN <<EOR
    CUDA_SHORT_VERSION=${CUDA_VERSION%.*}
    conda create -y -n "alltalk" -c conda-forge python=${PYTHON_VERSION}
    conda activate alltalk
    conda install -y \
      gcc_linux-64 \
      gxx_linux-64 \
      libaio \
      faiss-gpu=1.9.0 \
      cuda=${CUDA_VERSION} cuda-tools=${CUDA_VERSION} cuda-toolkit=${CUDA_VERSION} cuda-version=${CUDA_SHORT_VERSION} \
      cuda-command-line-tools=${CUDA_VERSION} cuda-compiler=${CUDA_VERSION} cuda-runtime=${CUDA_VERSION} \
      cuda-libraries=${CUDA_VERSION} cuda-libraries-dev=${CUDA_VERSION} cuda-libraries-static=${CUDA_VERSION} \
      cuda-cudart=${CUDA_SHORT_VERSION} cuda-cudart_linux-64=${CUDA_SHORT_VERSION} \
      conda-forge::nccl=2.27.5.1 \
      cudnn=9.10 \
      py-cpuinfo=9 \
      conda-forge::ffmpeg=7.1.0 \
      conda-forge::portaudio=19.7.0 \
      -c pytorch \
      -c nvidia \
      -c anaconda

    if [ $? -ne 0 ] ; then
      echo "Failed to install conda dependencies: $RESULT"
      exit 1
    fi

    conda clean -a && pip cache purge
EOR

RUN <<EOR
  CUDA_SHORT_VERSION=${CUDA_VERSION%.*}
  CUDA_SHORT_VERSION_NO_DOT=${CUDA_SHORT_VERSION//./}

  conda activate alltalk
  mkdir -p ${ALLTALK_DIR}/pip_cache
  pip install --no-cache-dir --cache-dir=${ALLTALK_DIR}/pip_cache \
      torch==2.7.1 torchvision==0.22.1 torchaudio==2.7.1 --index-url https://download.pytorch.org/whl/cu${CUDA_SHORT_VERSION_NO_DOT}

  if [ $? -ne 0 ] ; then
    echo "Failed to install pip dependencies: $RESULT"
    exit 1
  fi
EOR

RUN <<EOR
# See https://gist.github.com/xkortex/5ae49d7e6e969405bd2c3152a949c1f1
cat << EOF > ${ALLTALK_DIR}/conda_env.sh
#!/usr/bin/env bash
source ~/.bashrc
__conda_setup="\$('/opt/conda/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
eval "\$__conda_setup"
unset __conda_setup

conda activate alltalk
EOF
EOR