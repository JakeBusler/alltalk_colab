<<<<<<< HEAD
FROM nvidia/cuda:12.1.1-devel-ubuntu22.04
ENV HOST 0.0.0.0
RUN apt-get update && apt-get upgrade -y \
    && apt-get install -y git build-essential portaudio19-dev \
    python3 python3-pip gcc wget \
    ocl-icd-opencl-dev opencl-headers clinfo \
    libclblast-dev libopenblas-dev libaio-dev \
    && mkdir -p /etc/OpenCL/vendors && echo "libnvidia-opencl.so.1" > /etc/OpenCL/vendors/nvidia.icd \
    && ln -s /usr/bin/python3 /usr/bin/python

WORKDIR /app
ENV CUDA_DOCKER_ARCH=all
COPY system/requirements/requirements_docker.txt system/requirements/requirements_docker.txt
RUN pip install --no-cache-dir --no-deps -r system/requirements/requirements_docker.txt && \
    pip install --no-cache-dir deepspeed
COPY . .

EXPOSE 7851 7852
RUN chmod +x launch.sh
ENTRYPOINT ["sh", "-c", "./launch.sh"]
=======
ARG DOCKER_REPOSITORY
ARG DOCKER_TAG=latest
FROM ${DOCKER_REPOSITORY}alltalk_tts_environment:${DOCKER_TAG}

# Argument to choose the model: piper, vits, xtts
ARG TTS_MODEL="xtts"
ENV TTS_MODEL=$TTS_MODEL

ARG DEEPSPEED_VERSION=0.17.2
ENV DEEPSPEED_VERSION=$DEEPSPEED_VERSION

ENV GRADIO_SERVER_NAME="0.0.0.0"

# Switch for using the multi engine manager:
ENV ALLTALK_ENABLE_MULTI_ENGINE_MANAGER=false

# Default settings used in docker_default_confignew.json:
ENV ALLTALK_DELETE_OUTPUT_WAVS="1"
ENV ALLTALK_GRADIO_INTERFACE=true
ENV ALLTALK_RVC_ENABLED=true
ENV ALLTALK_RVC_F0METHOD="rmvpe"

# Default settings used in docker_default_mem_config.json:
ENV ALLTALK_MEM_AUTO_START_ENGINES=1
ENV ALLTALK_MEM_MAX_INSTANCES=1

WORKDIR ${ALLTALK_DIR}

##############################################################################
# Download TTS models:
##############################################################################
COPY system/tts_engines/piper/available_models.json system/tts_engines/piper/
COPY system/tts_engines/vits/available_models.json system/tts_engines/vits/
COPY system/tts_engines/xtts/available_models.json system/tts_engines/xtts/
RUN <<EOR
    available_models="system/tts_engines/${TTS_MODEL}/available_models.json"
    first_start_model=$(cat ${available_models} | jq -r '.first_start_model')
    model=$(cat ${available_models} | jq ".models[] | select(.model_name==\"${first_start_model}\")")
    folder_path=$( echo "${model}" | jq -r '.folder_path // empty' )
    files_to_download=$( echo "${model}" | jq '.files_to_download[]?' )
    github_rls_url=$( echo "${model}" | jq '.github_rls_url // empty' )

    # Special case for vits: firstrun.py expects the ZIP download directly in the model folder.
    # When firstrun.py unzips the file, the correct folder will be created automatically.
    if [[ "$TTS_MODEL" == "vits" ]]; then
      folder_path=""
    fi

    # Merging both fields:
    files_to_download="${files_to_download} ${github_rls_url}"
    target_dir="models/${TTS_MODEL}/${folder_path}"

    echo "$files_to_download" | xargs -n 1 curl --create-dirs --output-dir "${target_dir}" -LO
EOR

##############################################################################
# Download all RVC models:
##############################################################################
COPY system/tts_engines/rvc_files.json system/tts_engines/
RUN jq -r '.[]' system/tts_engines/rvc_files.json | xargs -n 1 curl --create-dirs --output-dir models/rvc_base -LO

##############################################################################
# Install python dependencies (cannot use --no-deps because requirements are not complete)
##############################################################################
COPY system/config/*.whl system/config/
COPY system/requirements/requirements_standalone.txt system/requirements/requirements_standalone.txt
COPY system/requirements/requirements_parler.txt system/requirements/requirements_parler.txt
ENV PIP_CACHE_DIR=${ALLTALK_DIR}/pip_cache
RUN <<EOR
    conda activate alltalk

    mkdir -p ${ALLTALK_DIR}/pip_cache
    pip install --no-cache-dir --cache-dir=${ALLTALK_DIR}/pip_cache -r system/requirements/requirements_standalone.txt
    pip install --no-cache-dir --cache-dir=${ALLTALK_DIR}/pip_cache --upgrade gradio==4.32.2

    # By default, version 1.9.10 is used causing this warning on startup: 'FutureWarning: `torch.cuda.amp.autocast(args...)` is deprecated'
    pip install --no-cache-dir --cache-dir=${ALLTALK_DIR}/pip_cache local-attention==1.11.1

    # Parler:
    pip install --no-cache-dir --cache-dir=${ALLTALK_DIR}/pip_cache -r system/requirements/requirements_parler.txt

    conda clean --all --force-pkgs-dirs -y && pip cache purge
EOR

##############################################################################
# Install DeepSpeed
##############################################################################
RUN mkdir -p /tmp/deepspeed
COPY docker/deepspeed/build*/*.whl /tmp/deepspeed/
RUN <<EOR
    DEEPSPEED_WHEEL=$(realpath -q /tmp/deepspeed/*.whl)
    conda activate alltalk

    # Download DeepSpeed wheel if it was not built locally:
    if [ -z "${DEEPSPEED_WHEEL}" ] || [ ! -f $DEEPSPEED_WHEEL ] ; then
      echo "Downloading pre-built DeepSpeed wheel"
      CURL_ERROR=$( { curl --output-dir /tmp/deepspeed -fLO "https://github.com/erew123/alltalk_tts/releases/download/DeepSpeed-for-docker/deepspeed-0.17.2+15f054d9-cp311-cp311-linux_x86_64.whl" ; } 2>&1 )
      if [ $? -ne 0 ] ; then
        echo "Failed to download DeepSpeed: $CURL_ERROR"
        exit 1
      fi
      DEEPSPEED_WHEEL=$(realpath -q /tmp/deepspeed/*.whl)
    fi

    echo "Using precompiled DeepSpeed wheel at ${DEEPSPEED_WHEEL}"
    CFLAGS="-I$CONDA_PREFIX/include/" LDFLAGS="-L$CONDA_PREFIX/lib/" \
      pip install --no-cache-dir ${DEEPSPEED_WHEEL}

    if [ $? -ne 0 ] ; then
      echo "Failed to install pip dependencies: $RESULT"
      exit 1
    fi

    rm ${DEEPSPEED_WHEEL}
    conda clean --all --force-pkgs-dirs -y && pip cache purge
EOR

##############################################################################
# Writing scripts to start alltalk:
##############################################################################
RUN <<EOR
    cat << EOF > start_alltalk.sh
#!/usr/bin/env bash
source ~/.bashrc

replace_env_vars() {
  echo "{}" > /tmp/empty.json
  jq "\$( cat \$1 ) | del(.. | select(. == null))" /tmp/empty.json > \$1.tmp
  mv \$1.tmp \$1
  rm -f /tmp/empty.json
}

merge_json_files() {
  # Merging JSON config with docker default values followed by values set on startup:
  jq -s '.[0] * .[1] * .[2]' \$1 docker_default_\$1 docker_\$1  > \$1.tmp
  mv \$1.tmp \$1
}

replace_env_vars docker_default_confignew.json
merge_json_files confignew.json

# Script for deleting WAV files that are older than 1 minute:
cat << EOF2 > ${ALLTALK_DIR}/cleanup-wavs.sh
#!/usr/bin/env bash
[ \"\$ALLTALK_AUTO_CLEANUP\" = \"true\" ] && find ${ALLTALK_DIR}/outputs -type f -name "*.wav" -mmin +1 -exec rm {} \;
EOF2
chmod u+x ${ALLTALK_DIR}/cleanup-wavs.sh

# Starting the cron job:
cron

source ${ALLTALK_DIR}/conda_env.sh

if [ "\$ALLTALK_ENABLE_MULTI_ENGINE_MANAGER" = "true" ] ; then
  echo "Starting alltalk using multi engine manager"
  replace_env_vars docker_default_mem_config.json
  merge_json_files mem_config.json
  python tts_mem.py
else
  echo "Starting alltalk"
  python script.py
fi
EOF
    cat << EOF > start_finetune.sh
#!/usr/bin/env bash
source ~/.bashrc
export TRAINER_TELEMETRY=0
source ${ALLTALK_DIR}/conda_env.sh
python finetune.py
EOF
    cat << EOF > start_diagnostics.sh
#!/usr/bin/env bash
source ~/.bashrc
source ${ALLTALK_DIR}/conda_env.sh
python diagnostics.py
EOF
    chmod +x start_alltalk.sh
    chmod +x start_finetune.sh
    chmod +x start_diagnostics.sh
EOR

COPY --chown=alltalk:alltalk . .

RUN mkdir -p ${ALLTALK_DIR}/outputs ${ALLTALK_DIR}/.triton/autotune

##############################################################################
# Enable deepspeed for all models:
##############################################################################
RUN find . -name model_settings.json -exec sed -i -e 's/"deepspeed_enabled": false/"deepspeed_enabled": true/g' {} \;

##############################################################################
# Cronjob running every minute to delete output WAV files:
##############################################################################
USER root
RUN <<EOR
    echo "* * * * * ${ALLTALK_DIR}/cleanup-wavs.sh" > /etc/cron.d/cleanup-wavs
    crontab -u alltalk /etc/cron.d/cleanup-wavs
    chmod u+s /usr/sbin/cron
EOR

USER alltalk

##############################################################################
# Create script to execute firstrun.py and run it:
##############################################################################
RUN echo $'#!/usr/bin/env bash \n\
source ~/.bashrc \n\
source ${ALLTALK_DIR}/conda_env.sh \n\
python ./system/config/firstrun.py $@' > ./start_firstrun.sh

RUN chmod +x start_firstrun.sh
RUN ./start_firstrun.sh --tts_model $TTS_MODEL

##############################################################################
# Start alltalk:
##############################################################################
ENTRYPOINT ["bash", "-c", "./start_alltalk.sh"]
>>>>>>> f16117e95b540e9bbbd8247b49ca6c6b1350b172
