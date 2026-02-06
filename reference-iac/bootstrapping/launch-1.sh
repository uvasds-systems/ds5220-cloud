#!/bin/bash

# ubuntu 24.04LTS

aws ec2 run-instances \
  --image-id ami-0b6c6ebed2801a5cb \
  --count 1 \
  --instance-type t3.micro \
  --key-name ds5220 \
  --security-group-ids sg-066412c1406b41de3 \
  --user-data file://bootstrap-1.sh
