# Strimzi Blast Radius Upgrade Demo

This repository contains scripts and resources for demonstrating a phased upgrade process for the Strimzi Kafka Operator.
This allows users to control the blast radius of those upgrades by deploying multiple Strimzi versions simultaneously and handing control of Kafka clusters between them using labels. 

## Key Components

- **download-install-files.sh**: Script that downloads Strimzi operator resources from a specific git tag and sets up the various Kustomization files and patches needed to alter the install files.
- **Kustomization files**: Manages resource modifications including name suffixes and reference updates.
- **Patches**: Specialized kustomize patches for handling service accounts, role bindings, and deployment references.

## Usage Instructions

### Downloading Operator Resources

The main script `download-install-files.sh` downloads the Strimzi Cluster Operator resources from a specific git tag and adds them to the overall Operator installation set.

```shell
./scripts/download-install-files.sh <git-tag> [--keep-crds | --upgrade-crds] [--namespace=NAMESPACE] 
```

Options:

- `<git-tag>`: Required. The Strimzi git tag to download (e.g., 0.43.0)
- `--keep-crds`: Keep CRD YAML files in the operator directory (default is to delete them). This is for development.
- `--upgrade-crds`: This option allows you to specify that the CRDs from this git-tag should be used as the global CRDs for teh installation set. It will move the CRD files to the install-files/crds directory and add a version suffix to the filenames. 
- `--namespace=NAMESPACE`: Set the target namespace for the operator installation. If not specified, the namespace will not be set in the resources.

Examples:

```shell
# Download version 0.43.0, removing its CRDs (the default behavior), this will leave the operator namespace as 'my-project'
./scripts/download-install-files.sh 0.43.0

# Download version 0.44.0 and set the operator namespace to 'strimzi'
./scripts/download-install-files.sh 0.44.0 --namespace=stimzi

# Download version 0.45.0, set the operator namespace and upgrade the global CRDs to be that version's
./scripts/download-install-files.sh 0.45.0 --namespace=strimzi --upgrade-crds

```

### Installing the operator set

Once you have added all the versions you wish to support and designated the most recent versions CRDs (using the `--upgrade-crds` flag), you can install the Operator set by running:

```shell
kubectl -n strimzi apply -k install-files
```

## Testing the phased upgrade

To test the hand-off between Strimzi version you can deploy the set of Kafka brokers in the `tests` folder:

```shell
kubectl -n kafka apply -f tests
```

This will deploy 3 Kafka clusters all managed by the 0.43 operator.
In order to move a cluster to another operator simply change the `strimzi-resource-selector` label to point at the one assigned to that operator.
The labels all have the format `strimzi-<major>-<minor>-<micro>`. 
For example the 0.43.0 Operator will manage CRs with the label `strimzi-0-43-0`. 
The label for a given Operator deployment can be found with the following command:

```shell
kubectl -n strimzi get deployments <operator-deployment-name> -o json | \
    jq --arg "name" "STRIMZI_CUSTOM_RESOURCE_SELECTOR" \
    '.spec.template.spec.containers[0].env.[] | select(.name == $name) | .value'
```

For example move `test-kafka-1` from the 0.43 operator to the 0.44: 
```shell
kubectl -n kafka label --overwrite kafka test-kafka-1 strimzi-resource-selector=strimzi-0-44-0
```

