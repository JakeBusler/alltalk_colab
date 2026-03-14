#!/usr/bin/env bash

declare -A ALLTALK_VARS
ALLTALK_VARS["CUDA_VERSION"]=12.8.1
ALLTALK_VARS["PYTHON_VERSION"]=3.11.11
ALLTALK_VARS["DEEPSPEED_VERSION"]=0.17.2

# Export single variables (needed by Docker locally)
for key in "${!ALLTALK_VARS[@]}"
do
  export "${key}=${ALLTALK_VARS[${key}]}"
done

# Export the entire associative array (needed by Github action)
export ALLTALK_VARS