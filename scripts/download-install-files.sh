#!/bin/bash

# Function to generate resources list for kustomization.yaml file in a specified directory
generate_resources_list() {
  local directory=$1
  
  # Change to the target directory
  pushd "$directory" > /dev/null || return 1
  
  echo "Generating resources list for kustomization.yaml in $directory..."
  
  # Start with an empty kustomization.yaml file
  echo "resources:" > kustomization.yaml
  
  # First, add all directories
  for dir in $(find . -maxdepth 1 -type d | grep -v "^\.$" | sort); do
    # Remove the leading './' from directory names
    dir_name=${dir#./}
    # Skip patches directory and hidden directories
    if [[ "$dir_name" != "patches" && "$dir_name" != .* ]]; then
      echo "  - $dir_name" >> kustomization.yaml
    fi
  done
  
  # Then add all YAML files
  for file in $(find . -maxdepth 1 -type f -name "*.yaml" | sort); do
    # Remove the leading './' from file names
    file_name=${file#./}
    # Skip kustomization.yaml itself
    if [[ "$file_name" != "kustomization.yaml" ]]; then
      echo "  - $file_name" >> kustomization.yaml
    fi
  done
  
  # Return to original directory
  popd > /dev/null
  return 0
}

# Function to show usage information
show_usage() {
  echo "Usage: $0 <git-tag> --namespace=NAMESPACE [--keep-crds | --upgrade-crds]"
  echo
  echo "Options:"
  echo "  --namespace=NAMESPACE Set the namespace for all resources (required)"
  echo "  --keep-crds           Keep all CRD YAML files (default is to delete them)"
  echo "  --upgrade-crds        Use the CRD YAML files to replace those in the install-files/crds directory"
}

# Check if a tag argument was provided
if [ -z "$1" ]; then
  echo "Error: Please provide a git tag as an argument."
  show_usage
  exit 1
fi

# Parse command line arguments
GIT_TAG=$1
shift

CRD_ACTION="delete"  # Default action is to delete CRDs
NAMESPACE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --keep-crds)
      CRD_ACTION="keep"
      shift
      ;;
    --upgrade-crds)
      CRD_ACTION="move"
      shift
      ;;
    --namespace=*)
      NAMESPACE="${1#*=}"
      shift
      ;;
    *)
      echo "Error: Unknown option $1"
      show_usage
      exit 1
      ;;
  esac
done

# Check if namespace was provided
if [ -z "$NAMESPACE" ]; then
  echo "Error: Namespace is required. Please provide it using --namespace=NAMESPACE"
  show_usage
  exit 1
fi

# Set variables
TEMP_DIR=$(mktemp -d)
TARGET_DIR="install-files/cluster-operator-${GIT_TAG}"
CRD_TARGET_DIR="install-files/crds"
# Generate a sanitized version of the git tag for use in resource names
# Replace dots with dashes for Kubernetes compatibility
SANITIZED_GIT_TAG="${GIT_TAG//./\-}"

# Create target directory if it doesn't exist
mkdir -p "$TARGET_DIR"

echo "Downloading Strimzi resources for tag: $GIT_TAG"
echo "Target directory: $TARGET_DIR"
echo "Target namespace: $NAMESPACE"

# Clone the repository to a temporary directory
echo "Cloning repository..."
git -c advice.detachedHead=false clone --depth 1 --branch "$GIT_TAG" https://github.com/strimzi/strimzi-kafka-operator.git "$TEMP_DIR" || {
  echo "Error: Failed to clone the repository with tag $GIT_TAG."
  rm -rf "$TEMP_DIR"
  exit 1
}

# Copy the cluster-operator directory contents
echo "Copying resources..."
if [ -d "$TEMP_DIR/install/cluster-operator" ]; then
  cp -r "$TEMP_DIR/install/cluster-operator"/* "$TARGET_DIR"
  echo "Resources successfully copied to $TARGET_DIR"
else
  echo "Error: install/cluster-operator directory not found in the repository."
  rm -rf "$TEMP_DIR"
  exit 1
fi

# Handle CRD files according to specified action
if [ "$CRD_ACTION" = "delete" ]; then
  echo "Deleting CRD files..."
  find "$TARGET_DIR" -name "*.yaml" | xargs grep -l "crd" | xargs rm -f
  echo "CRD files deleted."
elif [ "$CRD_ACTION" = "move" ]; then
  echo "Moving CRD files to $CRD_TARGET_DIR..."
  # Remove existing CRD directory if it exists and recreate it
  rm -rf "$CRD_TARGET_DIR"
  mkdir -p "$CRD_TARGET_DIR"
  
  for file in $(find "$TARGET_DIR" -name "*.yaml" | xargs grep -l "crd"); do
    # Get just the filename without the path
    filename=$(basename "$file")
    # Split the filename and extension
    base_name="${filename%.*}"
    extension="${filename##*.}"
    # Copy to the CRD directory with the tag as a suffix before the extension
    cp "$file" "$CRD_TARGET_DIR/${base_name}-${SANITIZED_GIT_TAG}.${extension}"
    # Remove the original file
    rm "$file"
  done
  echo "CRD files moved to $CRD_TARGET_DIR."
  
  # Generate resources list for CRDs directory
  generate_resources_list "$CRD_TARGET_DIR"
elif [ "$CRD_ACTION" = "keep" ]; then
  echo "Keeping CRD files as requested."
fi

# Check if a kustomization.yaml file already exists in the target directory
if [ -f "$TARGET_DIR/kustomization.yaml" ]; then
  echo "Warning: kustomization.yaml file already exists in $TARGET_DIR. It will be overwritten."
  rm -f "$TARGET_DIR/kustomization.yaml"
fi

# Export variables for template substitution
export SANITIZED_GIT_TAG
export NAMESPACE

echo "Generating ClusterRoleBindings for cluster-wide reconciliation"

KUBECTL_CREATE="kubectl create --dry-run=client -o yaml"

$KUBECTL_CREATE clusterrolebinding strimzi-cluster-operator-namespaced \
--clusterrole=strimzi-cluster-operator-namespaced \
--serviceaccount $NAMESPACE:strimzi-cluster-operator > $TARGET_DIR/strimzi-cluster-operator-namespaced.yaml

$KUBECTL_CREATE clusterrolebinding strimzi-cluster-operator-watched \
--clusterrole=strimzi-cluster-operator-watched \
--serviceaccount $NAMESPACE:strimzi-cluster-operator > $TARGET_DIR/strimzi-cluster-operator-watched.yaml

$KUBECTL_CREATE clusterrolebinding strimzi-cluster-operator-entity-operator-delegation \
--clusterrole=strimzi-entity-operator \
--serviceaccount $NAMESPACE:strimzi-cluster-operator > $TARGET_DIR/strimzi-cluster-operator-entity-operator-delegation.yaml

echo "Generating kustomization.yaml file..."
# Generate resources list for the target directory
generate_resources_list "$TARGET_DIR"
# Add the additional patch information on to the end of the resources list
envsubst < templates/cluster-operator-kustomization-template.yaml >> "$TARGET_DIR/kustomization.yaml"
echo "Created $TARGET_DIR/kustomization.yaml"

# Create patches directory
mkdir -p "$TARGET_DIR/patches"

# Create patch-deployment.yaml for kustomize
envsubst < templates/patch-deployment-template.yaml > "$TARGET_DIR/patches/patch-deployment.yaml"
echo "Created $TARGET_DIR/patches/patch-deployment.yaml"

# Create patch-role-reference.yaml for kustomize
envsubst < templates/patch-role-references-template.yaml > "$TARGET_DIR/patches/patch-role-references.yaml"
echo "Created $TARGET_DIR/patches/patch-role-references.yaml"

# Check if a kustomization.yaml file already exists in the target directory
INSTALL_DIR="install-files"
if [ -f "$INSTALL_DIR/kustomization.yaml" ]; then
  echo "Regenerating $INSTALL_DIR/kustomization.yaml"
  rm -f "$INSTALL_DIR/kustomization.yaml"
else
  echo "Generating $INSTALL_DIR/kustomization.yaml"
fi

# Create top level kustomization.yaml file
generate_resources_list $INSTALL_DIR

unset $SANITIZED_GIT_TAG
unset $NAMESPACE

# Clean up temporary directory
rm -rf "$TEMP_DIR"
echo "Temporary files cleaned up"

echo "Done! Strimzi cluster operator resources for tag $GIT_TAG have been added to the installation set"
printf "\nFor resources to be managed by this operator add the following label:\n"
printf "\nstrimzi-resource-selector=strimzi-$SANITIZED_GIT_TAG\n\n"
