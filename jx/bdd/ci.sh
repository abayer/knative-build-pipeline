#!/usr/bin/env bash
set -e
set -x

export GH_USERNAME="jenkins-x-bot-test"
export GH_EMAIL="jenkins-x@googlegroups.com"
export GH_OWNER="jenkins-x-bot-test"

export REPORTS_DIR="${BASE_WORKSPACE}/build/reports"
export GINKGO_ARGS="-v"

# fix broken `BUILD_NUMBER` env var
export BUILD_NUMBER="$BUILD_ID"

# Release the snapshot chart
make release

export JX_HOME="/tmp/jxhome"
export KUBECONFIG="/tmp/jxhome/config"

mkdir -p $JX_HOME

# lets avoid the git/credentials causing confusion during the test
export XDG_CONFIG_HOME=$JX_HOME

jx install dependencies --all

jx --version

mkdir -p $JX_HOME/git
# replace the credentials file with a single user entry
echo "https://$GH_USERNAME:$GH_ACCESS_TOKEN@github.com" > $JX_HOME/git/credentials

gcloud auth activate-service-account --key-file $GKE_SA

# lets setup git
git config --global --add user.name JenkinsXBot
git config --global --add user.email jenkins-x@googlegroups.com

echo "running the BDD tests with JX_HOME = $JX_HOME"

# setup jx boot parameters
export JX_VALUE_ADMINUSER_PASSWORD="$JENKINS_PASSWORD" # pragma: allowlist secret
export JX_VALUE_PIPELINEUSER_USERNAME="$GH_USERNAME"
export JX_VALUE_PIPELINEUSER_EMAIL="$GH_EMAIL"
export JX_VALUE_PIPELINEUSER_TOKEN="$GH_ACCESS_TOKEN"
export JX_VALUE_PROW_HMACTOKEN="$GH_ACCESS_TOKEN"

# TODO temporary hack until the batch mode in jx is fixed...
export JX_BATCH_MODE="true"

# Use the latest boot config promoted in the version stream instead of master to avoid conflicts during boot, because
# boot fetches always the latest version available in the version stream.
git clone  https://github.com/jenkins-x/jenkins-x-versions.git versions
export BOOT_CONFIG_VERSION=$(jx step get dependency-version --host=github.com --owner=jenkins-x --repo=jenkins-x-boot-config --dir versions | sed 's/.*: \(.*\)/\1/')
git clone https://github.com/jenkins-x/jenkins-x-boot-config.git boot-source
cd boot-source
git checkout tags/v${BOOT_CONFIG_VERSION} -b latest-boot-config

cp ../jx/bdd/jx-requirements.yml .
cp ../jx/bdd/parameters.yaml env
sed -e s/\$VERSION/${VERSION}/g ../jx/bdd/helm-requirements.yaml.template > env/requirements.yaml

# TODO hack until we fix boot to do this too!
helm init --client-only
helm repo add jenkins-x https://storage.googleapis.com/chartmuseum.jenkins-x.io

set +e
jx step bdd \
    --versions-repo https://github.com/jenkins-x/jenkins-x-versions.git \
    --config ../jx/bdd/cluster.yaml \
    --gopath /tmp \
    --git-provider=github \
    --git-username $GH_USERNAME \
    --git-owner $GH_OWNER \
    --git-api-token $GH_ACCESS_TOKEN \
    --default-admin-password $JENKINS_PASSWORD \
    --no-delete-app \
    --no-delete-repo \
    --tests test-verify-pods \
    --tests test-create-spring

bdd_result=$?
cd ..
make delete-from-chartmuseum

exit $bdd_result
