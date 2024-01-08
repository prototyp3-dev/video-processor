# Video processor

```
Cartesi Rollups version: 1.0.x
```

This DApp is a simple example to push and pull data from Celestia and then process in a cartesi dapp.

## Why Cartesi and Celestia?

There are severe limitations on the kind of computations you can do on the blockchain in L1s like Ethereum and those are due to the very expensive and limited amount of data you can input and the expensive, limited and non-ergonomical processing you can perform.

About the data, at the time of writting, the estimated cost on Ethereum would be a steep $1000 cost to send a 1MB video as calldata, so Celestia enables what would otherwise be prohibitely expensive data inputs for applications.
On the processing side, the Cartesi Machine allows deterministic use of complex libraries like OpenCV effortlessly, emulating RISC-V ISA supporting Linux and also enables computations that are multiple orders of magnitude larger than what´s feasible on an L1.

Processing a 1.4MB video sample (https://youtu.be/ypproaYVOxE?feature=shared&t=153) required 213,811,019,324 RISC-V cycles. Considering that currently the max gas on an Ethereum block is 30M gas and the cheapest useful OPCODE is 3 gas (ADD) the best case is 10M operations per block on Ethereum. This translates to approximately 21,381 Ethereum blocks (RISC-V cycles divided by max operations per block on Ethereum). To complete this video processing task, it would take around 71 hours on Ethereum, with blocks being generated every 12 seconds (Number of blocks needed multiplied by time between blocks).
On the cost side, multiplying the number of blocks (21,381) by the gas limit per block (30 million), the current gas price (32 gwei), and dividing to account the number of decimals in ETH (18), we get 20,525.76 ETH (21381×30×10^6×32×10^9÷10^18). At the ETH price of 2227.04 USD, the cost would be over 45M USD!

## What could this lead to?

- An application to prove you're the first to process a specific video in a distinctive manner, authenticated by a unique hash for that particular state
- A sovereign rollup implementatation in which state evolves by adding more processing steps to the updated video.
- Some other interesting use a smart developer could come up with :)

# Executing

## Requirements

You must have docker, git and go installed on your system. Besides, you need to install:

- [Sunodo](https://github.com/sunodo/sunodo) (To build and run the DApp backend)
- [celestia](https://docs.celestia.org/developers/node-tutorial) (To interact with celestia)

## Build Cartesi Machine

To build the cartesi machine with the rollup approach (same command as `sunodo build`):

```shell
./video-processor build-dapp
```

You can also build a template cartesi machine which runs a script with:

```shell
./video-processor build
```

## Celestia installation

Refer to celestia [docs](https://docs.celestia.org/developers/node-tutorial)

Build celestia (you will need [go](https://docs.celestia.org/developers/node-tutorial#install-golang)):

```shell
git clone https://github.com/celestiaorg/celestia-node.git
cd celestia-node/
git checkout tags/v0.12.0
make build
make install
```

Initialize node in [arabica](https://docs.celestia.org/nodes/arabica-devnet) testnet environment. See [mocha](https://docs.celestia.org/nodes/mocha-testnet) for mocha testnet.

```shell
celestia light init --p2p.network arabica
```

It will create a key. Write down the key and request tokens on the [faucet or discord](https://docs.celestia.org/nodes/arabica-devnet#arabica-devnet-faucet).

## Sending and retrieving data blob from celestia 

You should start the light node:

```shell
celestia light start --core.ip consensus-validator.celestia-arabica-10.com --p2p.network arabica
```

Save the celestia node store in a variable:

```shell
NODE_STORE=$HOME/.celestia-light-arabica-10
```

Convert the video to base 64 to input it to celestia (note: celestia network limits the data blob). Change `<video>` to your video and run:

```shell
videob64_path=$(mktemp)
tr -d '\n'  <<< $(base64 <video> ) > $videob64_path
```

Optionally, get the namespace for celestia based on rolluped Cartesi Machine hash (use `-x t` for template cartesi machine):

```shell
namespace=0x$(./video_processor.sh hash -b 10 -x r)
```

Finally, send the video to celestia

```shell
submit_result=$(./utils/celestia_blob_wo submit \
    $namespace \
    $videob64_path \
    --node.store $NODE_STORE)
echo $submit_result
```

It will display the output in the form:

```json
{
  "result": {
    "height": <height>,
    "commitment": <commitment>
  }
}
```

Set the `height` and `commitment`

```shell
height=$(jq -r '.result.height' <<< $submit_result)
commitment=$(jq -r '.result.commitment' <<< $submit_result)
```

With the `height` and `commitment` and `namespace` you can obtain the data blob again:

```shell
result=$(celestia blob get $height $namespace $commitment --node.store $NODE_STORE)
echo $result | jq | more
```

The output should be something like

```json
{
  "result": {
    "namespace": <namespace>,
    "data": <data>,
    "share_version": 0,
    "commitment": <commitment>
  }
}
```

As a final step, you should save the data to a file to send to the Cartesi Machine for processing. For that you have to convert it from base 64:

```shell
data_base64=$(jq -r '.result.data' <<< $result)
printf '%s' $data_base64 | base64 -d > video
```

## Processing the video

To process the video you can use the rolluped machine built with sunodo or you can use the cartesi machine template. To run the rolluped cartesi machine use:

```shell
./video_processor.sh process -i <video input> -o <video outinput> [-f frames per second] -x r 
```

You can also build a template cartesi machine which runs a script with

```shell
./video_processor.sh process -i <video input> -o <video outinput> [-f frames per second] [-x t (default)]
```
