#!/usr/bin/env python3
"""Run script.
"""
import base64
import logging
import shlex
import sys
import tempfile
from os import listdir
from os.path import splitext, isfile, join, isdir, expandvars
from typing import List

import boto3
from clinner.command import Type, command
from clinner.run.main import Main

logger = logging.getLogger("cli")


@command(
    command_type=Type.SHELL,
    args=((("--extra-tag",), {"help": "Create additional tags", "nargs": "*"}),),
    parser_opts={"help": "Build docker image"},
)
def build(*args, **kwargs) -> List[List[str]]:
    cmds = [shlex.split(f"docker build") + kwargs["tag"] + ["."] + list(args)]

    if kwargs["extra_tag"]:
        cmds += [shlex.split(f"docker tag {kwargs['tag']} {t}") for t in kwargs["extra_tag"]]

    return cmds


@command(
    command_type=Type.SHELL,
    args=((("--extra-tag",), {"help": "Create additional tags", "nargs": "*"}),
          (("-u", "--username"), {"help": "Docker Hub username"}),
          (("-p", "--password"), {"help": "Docker Hub password"}),
          (("--aws-ecr",), {"help": "URL of AWS ECR server that you need to login"})),
    parser_opts={"help": "Push docker image"}
)
def push(*args, **kwargs) -> List[List[str]]:
    cmds = []

    if kwargs["aws_ecr"]:
        ecr_client = boto3.client('ecr', region_name='eu-west-1')
        token = ecr_client.get_authorization_token()
        username, password = base64.b64decode(token['authorizationData'][0]['authorizationToken']).decode().split(':')
        cmds += [shlex.split(f"docker login -u {username} -p {password} {kwargs['aws_ecr']}")]

    if kwargs["username"] and kwargs["password"]:
        cmds += [shlex.split(f"docker login -u {kwargs['username']} -p {kwargs['password']}")]

    cmds += [shlex.split(f"docker push {kwargs['tag']}") + list(args)]

    if kwargs["extra_tag"]:
        cmds += [shlex.split(f"docker push {t}") + list(args) for t in kwargs["extra_tag"]]

    return cmds


@command(
    command_type=Type.SHELL,
    args=((("-f", "--file",), {
        "help": "Deployment file or directory where the k8s manifests are located. Manifests "
                "will be pre-processed and environment variables will be substituted inplace "
                "before applying", "required": True
    }),),
    parser_opts={"help": "Deploy to AWS EKS"},
)
def kubernetes_deploy(*args, **kwargs) -> List[List[str]]:
    """
    Apply resource files on Kubernetes cluster. Manifests are specified using --file argument, which can also be a
    directory containing several k8s manifests.

    Note that manifests will be pre-processed and environment variables will be substituted inplace before applying.
    """
    valid_ext = ('.json', '.yaml', '.yml')
    deploy_path = kwargs["file"]
    manifests = []
    if isdir(deploy_path):
        manifests = [f for f in listdir(deploy_path) if isfile(join(deploy_path, f)) and splitext(f)[1] in valid_ext]
    elif isfile(deploy_path) and splitext(deploy_path)[1] in valid_ext:
        manifests = [deploy_path]

    if not manifests:
        raise FileNotFoundError(f"No json/yaml/yml manifests were found on path '{deploy_path}'")

    logger.info(f'Collected manifests: {manifests}')
    out_d = tempfile.mkdtemp()
    for mf in manifests:
        with open(join(deploy_path, mf), 'r') as y, \
                tempfile.NamedTemporaryFile('w', dir=out_d, delete=False, suffix=f'_{mf}') as out:
            logger.info(f"Replacing {y.name} -> {out.name}")
            out.write(expandvars(y.read()))

    return [shlex.split(f"kubectl apply -v 3 -o yaml -f {out_d}")]


class Builder(Main):
    def add_arguments(self, parser: "argparse.ArgumentParser"):
        parser.add_argument("-t", "--tag", help="Docker image tag", default="latest")


if __name__ == "__main__":
    sys.exit(Builder().run(verbose=1))
