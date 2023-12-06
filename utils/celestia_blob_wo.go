package main

import (
	"fmt"
	"os"
	"context"

    "io/ioutil"
	"github.com/spf13/cobra"

	cmdnode "github.com/celestiaorg/celestia-node/cmd"
	"github.com/celestiaorg/celestia-node/blob"
)

var (
	fee      int64
	gasLimit uint64
)

func main() {
	err := run()
	if err != nil {
		os.Exit(1)
	}
}

func run() error {
	return rootCmd.ExecuteContext(context.Background())
}

var rootCmd = &cobra.Command{
	Use: "celestia_blob_wo [command]",
	Short: `
	    ____      __          __  _
	  / ____/__  / /__  _____/ /_(_)___ _   _       _______
	 / /   / _ \/ / _ \/ ___/ __/ / __  /  | | _  / / __  /
	/ /___/  __/ /  __(__  ) /_/ / /_/ /   | |/ // / /_/ /
	\____/\___/_/\___/____/\__/_/\__,_/    |__/|__/_____/
	`,
	Args: cobra.NoArgs,
	CompletionOptions: cobra.CompletionOptions{
		DisableDefaultCmd: false,
	},
	PersistentPreRunE: cmdnode.InitClient,
}


var submitCmd = &cobra.Command{
	Use:  "submit [namespace] [blobDataPath]",
	Args: cobra.ExactArgs(2),
	Short: "Submit the blob contained on given path at the given namespace.\n" +
		"Note:\n" +
		"* only one blob is allowed to submit through the RPC.\n" +
		"* fee and gas.limit params will be calculated automatically if they are not provided as arguments",
	RunE: func(cmd *cobra.Command, args []string) error {
		client, err := cmdnode.ParseClientFromCtx(cmd.Context())
		if err != nil {
			return err
		}
		defer client.Close()

		namespace, err := cmdnode.ParseV0Namespace(args[0])
		if err != nil {
			return fmt.Errorf("error parsing a namespace:%v", err)
		}

        fileBytes, err := ioutil.ReadFile(args[1])
        if err != nil {
          return fmt.Errorf("error reading blob path:%v", err)
        }

		parsedBlob, err := blob.NewBlobV0(namespace, fileBytes)
		if err != nil {
			return fmt.Errorf("error creating a blob:%v", err)
		}

		height, err := client.Blob.Submit(
			cmd.Context(),
			[]*blob.Blob{parsedBlob},
			&blob.SubmitOptions{Fee: fee, GasLimit: gasLimit},
		)

		response := struct {
			Height     uint64          `json:"height"`
			Commitment blob.Commitment `json:"commitment"`
		}{
			Height:     height,
			Commitment: parsedBlob.Commitment,
		}
		return cmdnode.PrintOutput(response, err, nil)
	},
}


func init() {
	submitCmd.PersistentFlags().Int64Var(
		&fee,
		"fee",
		-1,
		"specifies fee (in utia) for blob submission.\n"+
			"Fee will be automatically calculated if negative value is passed [optional]",
	)

	submitCmd.PersistentFlags().Uint64Var(
		&gasLimit,
		"gas.limit",
		0,
		"sets the amount of gas that is consumed during blob submission [optional]",
	)

	// unset the default value to avoid users confusion
	submitCmd.PersistentFlags().Lookup("fee").DefValue = "0"

	rootCmd.PersistentFlags().AddFlagSet(cmdnode.RPCFlags())
	rootCmd.AddCommand(submitCmd)
	rootCmd.SetHelpCommand(&cobra.Command{})
}
