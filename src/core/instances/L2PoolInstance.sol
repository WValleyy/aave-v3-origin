// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {L2Pool} from '../contracts/protocol/pool/L2Pool.sol';
import {IPoolAddressesProvider} from '../contracts/interfaces/IPoolAddressesProvider.sol';
import {PoolInstance} from './PoolInstance.sol';

contract L2PoolInstance is L2Pool, PoolInstance {
  constructor(IPoolAddressesProvider provider) PoolInstance(provider) {}
}
