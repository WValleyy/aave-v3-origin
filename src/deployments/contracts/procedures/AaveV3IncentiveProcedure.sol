// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {EmissionManager} from 'aave-v3-periphery/contracts/rewards/EmissionManager.sol';
import {RewardsController} from 'aave-v3-periphery/contracts/rewards/RewardsController.sol';

contract AaveV3IncentiveProcedure {
  function _deployIncentives(address tempOwner) internal returns (address, address) {
    address emissionManager = address(new EmissionManager(tempOwner));
    address rewardsControllerImplementation = address(new RewardsController(emissionManager));
    RewardsController(rewardsControllerImplementation).initialize(address(0));

    return (emissionManager, rewardsControllerImplementation);
  }
}
