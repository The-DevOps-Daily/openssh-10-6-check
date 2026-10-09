// Minimal golang.org/x/crypto/ssh client: connect, run `true`, exit.
// Usage: goclient <host:port> <user> <private key>
package main

import (
	"fmt"
	"os"

	"golang.org/x/crypto/ssh"
)

func main() {
	key, err := os.ReadFile(os.Args[3])
	if err != nil {
		panic(err)
	}
	signer, err := ssh.ParsePrivateKey(key)
	if err != nil {
		panic(err)
	}
	cfg := &ssh.ClientConfig{
		User:            os.Args[2],
		Auth:            []ssh.AuthMethod{ssh.PublicKeys(signer)},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(), // throwaway local test server
	}
	conn, err := ssh.Dial("tcp", os.Args[1], cfg)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer conn.Close()
	s, err := conn.NewSession()
	if err != nil {
		panic(err)
	}
	if err := s.Run("true"); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
