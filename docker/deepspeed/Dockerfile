ARG DOCKER_REPOSITORY
ARG DOCKER_TAG=latest
FROM ${DOCKER_REPOSITORY}alltalk_tts_environment:${DOCKER_TAG}

ARG DEEPSPEED_VERSION=0.17.2
ENV DEEPSPEED_VERSION=$DEEPSPEED_VERSION

WORKDIR ${ALLTALK_DIR}

##############################################################################
# Install python dependencies
##############################################################################
ENV PIP_CACHE_DIR=/tmp/pip_cache
RUN <<EOR
  conda activate alltalk

  pip install \
      deepspeed-kernels
EOR


##############################################################################
# Clone DeepSpeed sources
##############################################################################
RUN <<EOR
  git clone https://github.com/microsoft/DeepSpeed.git ${ALLTALK_DIR}/DeepSpeed
  cd ${ALLTALK_DIR}/DeepSpeed
  git checkout .
  git checkout "tags/v${DEEPSPEED_VERSION}" -b "v${DEEPSPEED_VERSION}"
EOR

##############################################################################
# Create DeepSpeed build file
##############################################################################
RUN <<EOR
  cat << EOF > ${ALLTALK_DIR}/build_deepspeed.sh
#!/usr/bin/env bash
source ${ALLTALK_DIR}/conda_env.sh
mkdir -p ${ALLTALK_DIR}/build

cd ${ALLTALK_DIR}/DeepSpeed
DS_BUILD_OPS=1 python setup.py build_ext -j8 bdist_wheel
mv ${ALLTALK_DIR}/DeepSpeed/dist/*.whl ${ALLTALK_DIR}/build
EOF
EOR

RUN chmod +x ${ALLTALK_DIR}/build_deepspeed.sh

##############################################################################
# Build DeepSpeed:
##############################################################################
ENTRYPOINT ["bash", "-c", "-l", "$ALLTALK_DIR/build_deepspeed.sh"]