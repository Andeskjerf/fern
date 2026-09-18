# Fern 🌿 <sub>Fleet of Ephemeral Runtime Nodes</sub>

## 🚧 WIP 🚧

This is still early WIP and does not do anything special just yet.

## 🤔 What is this?

Fern is intended to be a distributed scraper following a "fan-out and fan-in" pattern that should be able to handle arbitrary scraping tasks.

Fern is an all-in-one binary that handles all steps required to get a distributed cluster of workers up and running:

1. Builds a minimal VM image (~5MB) using NixOS that contains the worker code & provider secrets
2. Provisions & setups all resources required at a supported hosting provider
3. Spins up N amount of workers with the workload split up evenly between them
4. Spins up a storage node that persists the data from all workers
5. Once done, data can be pulled down to localhost
6. Finally, cleans up cloud resources

## 🤖 Running

The project is intended to be ran using Nix. There are multiple outputs configured to make it easy to run.

A hosting provider must be configured

### ☁️ Supported hosting providers

- Scaleway

Currently, environment variables are used to hold secrets. Scaleway is the only supported provider as of right now, so the environment variables reflect that.

```env
# Cloud provider keys
SCW_ACCESS_KEY=
SCW_SECRET_KEY=
SCW_DEFAULT_ORGANIZATION_ID=
SCW_DEFAULT_PROJECT_ID=

# S3 Object Storage keys
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
```

The output `fern-with-image` handles all steps required to run the application.
- Builds the VM image that holds our code
- Passes the path to the image to the `fern` binary
- `fern` handles the rest

```shell
nix run .#fern-with-image
```

## 🏗️ Highlevel overview

### 📡 Communication

ZMQ is intended to be the primary method of communication for inter-node communication & node control.

- Control & monitoring of nodes from localhost
- Pushing data from worker to storage

### 🐝 Worker node

Stateless worker that performs the scraping task itself.

Is supposed to be able to support arbitrary instructions for scraping tasks.

#### 🎛️ ZMQ ports

- Incoming control & monitoring
- Outbound data transfer to storage node

#### 🔁 Lifecycle

- Provisioned by localhost
- Active scraping task
- Cleanup on panic / done

### 💾 Storage node

Node with SQLite configured as the storage backend, used to persist & collect data from all worker nodes.

Initial plan is to hold the database in RAM, but proper filesystem support may be considered if RAM proves to be insufficient.

#### 🎛️ ZMQ ports

- Incoming control & monitoring
- Incoming data transfer from all worker nodes

#### 🔁 Lifecycle

- Provisioned by localhost
- External cleanup / cleanup on incoming command
