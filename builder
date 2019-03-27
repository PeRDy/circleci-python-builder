#!/usr/bin/env python3
"""Run script.
"""
import base64
import logging
import shlex
import sys
import tempfile
import os
import typing

import boto3
from clinner.command import Type, command
from clinner.run.main import Main

logger = logging.getLogger("cli")


@command(
    command_type=Type.SHELL_WITH_HELP,
    args=(
        (("-t", "--tag"), {"help": "Docker image tag", "required": True}),
        (("--extra-tag",), {"help": "Create additional tags", "nargs": "*"}),
        (("--cache-from",), {"help": "Docker cache file to read"}),
        (("--store-image",), {"help": "Path to store Docker image"}),
    ),
    parser_opts={"help": "Build docker image"},
)
def build(*args, **kwargs) -> typing.List[typing.List[str]]:
    cmds = []

    # Load cached image if proceed and build
    if kwargs["cache_from"] and os.path.exists(kwargs["cache_from"]):
        logger.info("Loading docker image from %s", kwargs["cache_from"])
        cmds += load(file=kwargs["cache_from"])
        cmds += [shlex.split(f"docker build --cache-from={kwargs['tag']} -t {kwargs['tag']} .") + list(args)]
    else:
        cmds += [shlex.split(f"docker build -t {kwargs['tag']} .") + list(args)]

    # Extra tags
    if kwargs["extra_tag"]:
        cmds += tag(tag=kwargs["tag"], new_tag=kwargs["extra_tag"])

    # Cache built image
    if kwargs["store_image"]:
        logger.info("Saving docker image to %s", kwargs["store_image"])
        cmds += save(tag=kwargs["tag"], file=kwargs["store_image"])

    return cmds


@command(
    command_type=Type.SHELL_WITH_HELP,
    args=((("tag",), {"help": "Docker image tag"}), (("new_tag",), {"help": "New tag", "nargs": "+"})),
    parser_opts={"help": "Tag docker image"},
)
def tag(*args, **kwargs) -> typing.List[typing.List[str]]:
    return [shlex.split(f"docker tag {kwargs['tag']} {t}") for t in kwargs["new_tag"]]


@command(
    command_type=Type.SHELL_WITH_HELP,
    args=((("tag",), {"help": "Docker image tag"}), (("file",), {"help": "File path"})),
    parser_opts={"help": "Save docker image to file"},
)
def save(*args, **kwargs) -> typing.List[typing.List[str]]:
    os.makedirs(os.path.dirname(kwargs["file"]), exist_ok=True)
    return [shlex.split(f"docker save -o {kwargs['file']} {kwargs['tag']}")]


@command(
    command_type=Type.SHELL_WITH_HELP,
    args=((("file",), {"help": "File path"}),),
    parser_opts={"help": "Load docker image from file"},
)
def load(*args, **kwargs) -> typing.List[typing.List[str]]:
    return [shlex.split(f"docker load -i {kwargs['file']}")]


@command(
    command_type=Type.SHELL_WITH_HELP,
    args=(
        (("-t", "--tag"), {"help": "Tags to push", "nargs": "+"}),
        (("-u", "--username"), {"help": "Docker Hub username"}),
        (("-p", "--password"), {"help": "Docker Hub password"}),
        (("--aws-ecr",), {"help": "URL of AWS ECR server that you need to login"}),
    ),
    parser_opts={"help": "Push docker image"},
)
def push(*args, **kwargs) -> typing.List[typing.List[str]]:
    cmds = []

    # Login to AWS ECR using aws credentials
    if kwargs["aws_ecr"]:
        ecr_client = boto3.client("ecr", region_name="eu-west-1")
        token = ecr_client.get_authorization_token()
        username, password = base64.b64decode(token["authorizationData"][0]["authorizationToken"]).decode().split(":")
        cmds += [shlex.split(f"docker login -u {username} -p {password} {kwargs['aws_ecr']}")]

    # Login to Docker hub
    if kwargs["username"] and kwargs["password"]:
        cmds += [shlex.split(f"docker login -u {kwargs['username']} -p {kwargs['password']}")]

    # Push tags
    cmds += [shlex.split(f"docker push {t}") + list(args) for t in kwargs["tag"]]

    return cmds


@command(
    command_type=Type.SHELL_WITH_HELP,
    args=(
        (
            ("-f", "--file"),
            {
                "help": "Deployment file or directory where the k8s manifests are located. Manifests will be "
                "pre-processed and environment variables will be substituted inplace before applying",
                "required": True,
            },
        ),
    ),
    parser_opts={"help": "Deploy to AWS EKS"},
)
def kubernetes_deploy(*args, **kwargs) -> typing.List[typing.List[str]]:
    """
    Apply resource files on Kubernetes cluster. Manifests are specified using --file argument, which can also be a
    directory containing several k8s manifests.

    Note that manifests will be pre-processed and environment variables will be substituted inplace before applying.
    """
    valid_ext = (".json", ".yaml", ".yml")
    deploy_path = kwargs["file"]
    manifests = []
    if os.path.isdir(deploy_path):
        manifests = [
            manifest
            for manifest in os.listdir(deploy_path)
            if os.path.isfile(os.path.join(deploy_path, manifest)) and os.path.splitext(manifest)[1] in valid_ext
        ]
    elif os.path.isfile(deploy_path) and os.path.splitext(deploy_path)[1] in valid_ext:
        manifests = [deploy_path]

    if not manifests:
        raise FileNotFoundError(f"No json/yaml/yml manifests were found on path '{deploy_path}'")

    logger.info(f"Collected manifests: {manifests}")
    out_d = tempfile.mkdtemp()
    for mf in manifests:
        with open(os.path.join(deploy_path, mf), "r") as y, tempfile.NamedTemporaryFile(
            "w", dir=out_d, delete=False, suffix=f"_{mf}"
        ) as out:
            logger.info(f"Replacing {y.name} -> {out.name}")
            out.write(os.path.expandvars(y.read()))

    return [shlex.split(f"kubectl apply -v 3 -o yaml -f {out_d}")]


class Builder(Main):
    def add_arguments(self, parser: "argparse.ArgumentParser"):
        parser.add_argument("-t", "--tag", help="Docker image tag", default="latest")


if __name__ == "__main__":
    sys.exit(Builder().run(verbose=1))
