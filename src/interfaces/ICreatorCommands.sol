// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICreatorCommands {
  enum CreatorActions {
    NO_OP,
    SEND_ETH,
    MINT
  }

  struct Command {
    CreatorActions method;
    bytes args;
  }
}