# Video processor

```
Cartesi Rollups version: 1.0.x
```

This DApp is a simple example to push and pull data from Celestia and then process in a cartesi dapp.

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

Initialize node in testnet environment

```shell
celestia light init --p2p.network arabica
```

It will create a key. Write down the key and request tokens on the [faucet or discord](https://docs.celestia.org/nodes/arabica-devnet#arabica-devnet-faucet).

## Sending and retrieving data blob from celestia 

You should start the ligh node in [arabica](https://docs.celestia.org/nodes/arabica-devnet#bridge-full-and-light-nodes) network. See [mocha](https://docs.celestia.org/nodes/mocha-testnet) for mocha testnet.

```shell
celestia light start --core.ip consensus-validator.celestia-arabica-10.com --p2p.network arabica
```

Save the celestia node store n a variable:

```shell
NODE_STORE=$HOME/.celestia-light-arabica-10
```

Convert the video to hex to input it to celestia (Obs: celestia network limits the data blob). Run (change `<video>` to your video):

```shell
videob64=$(tr -d '\n'  <<< $(base64 <video> ) )
```

Get the namespace for celestia (based on rolluped CM hash):

```shell
namespace=0x$(./video_processor.sh hash -b 10 -x r)
```

Finally, send the video to celestia

```shell
celestia blob submit \
    $namespace \
    $videob64 \
    --node.store $NODE_STORE
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
height=<height>
commitment=<commitment>
```

With the `height` and `commitment` and `namespace` you can obtain the data blob again:

```shell
celestia blob get \
    $height $namespace $commitment \
    --node.store $NODE_STORE
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

As a final step, you should save the data to a file to send to the Cartesi Machine for processing. For that you might have to convert it from base 64:

```shell
result=$(celestia blob get $height $namespace $commitment --node.store $NODE_STORE)
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
