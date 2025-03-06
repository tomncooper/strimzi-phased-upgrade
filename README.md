# Strimzi Blast Radius Upgrade Demo

This repository contains scripts and resources for demonstrating an upgrade process for the Strimzi Kafka Operator which controls the blast radius of those upgrades.

## Overview

The primary purpose of this demo is to show how to safely upgrade Strimzi Kafka Operators by:

1. Installing multiple versions of the Strimzi cluster operator side by side.
2. Managing Custom Resource Definitions (CRDs) separately.
3. Using Kustomize to control alter the names and other references in the install files to allow operator installations to co-exist.
4. Demonstrating the blast radius control when upgrading.

This approach allows for controlled, incremental upgrades of Strimzi Kafka components while ensuring minimal impact on running Kafka clusters.

## Key Components

- **download-install-files.sh**: Script that downloads Strimzi operator resources from a specific git tag and sets up the various Kustomization files and patches needed to alter the install files.
- **Kustomization files**: Manages resource modifications including name suffixes and reference updates
- **Patches**: Specialized patches for handling service accounts, role bindings, and deployment references

## Usage Instructions

### Downloading Operator Resources

The main script `download-install-files.sh` downloads the Strimzi Cluster Operator resources from a specific git tag and adds them to the overall installation set.

```shell
./scripts/download-install-files.sh <git-tag> [--keep-crds | --upgrade-crds] [--namespace=NAMESPACE] 
```

Options:

- `<git-tag>`: Required. The Strimzi git tag to download (e.g., 0.43.0)
- `--keep-crds`: Keep CRD YAML files in the operator directory (default is to delete them). This is for development.
- `--upgrade-crds`: This option allows you to specify that the CRDs from this git-tag should be used as the global CRDs for teh installation set. It will move the CRD files to the install-files/crds directory and add a version suffix to the filenames. 
- `--namespace=NAMESPACE`: Set the target namespace for the operator installation. If not specified, the namespace will not be set in the resources.

```shell
# Download version 0.43.0, removing its CRDs (the default behavior)
./scripts/download-install-files.sh 0.43.0

# Download version 0.44.0 and set the target namespace to 'kafka-system'
./scripts/download-install-files.sh 0.44.0 --namespace=kafka-system

# Download version 0.45.0 and upgrade the global CRDs to be that version's
./scripts/download-install-files.sh 0.45.0 --namespace=kafka-system --upgrade-crds

```