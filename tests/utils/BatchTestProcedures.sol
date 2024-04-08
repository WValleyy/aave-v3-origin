// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';
import '../../src/deployments/interfaces/IMarketReportTypes.sol';
import {DeployUtils} from '../../src/deployments/contracts/utilities/DeployUtils.sol';
import {AaveV3GettersBatchOne} from '../../src/deployments/projects/aave-v3-batched/batches/AaveV3GettersBatchOne.sol';
import {AaveV3GettersBatchTwo} from '../../src/deployments/projects/aave-v3-batched/batches/AaveV3GettersBatchTwo.sol';
import {AaveV3SetupBatch} from '../../src/deployments/projects/aave-v3-batched/batches/AaveV3SetupBatch.sol';
import {FfiUtils} from '../../src/deployments/contracts/utilities/FfiUtils.sol';
import {DefaultMarketInput} from '../../src/deployments/inputs/DefaultMarketInput.sol';
import {AaveV3BatchOrchestration} from '../../src/deployments/projects/aave-v3-batched/AaveV3BatchOrchestration.sol';
import {IPoolAddressesProvider} from 'aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol';
import {ACLManager} from 'aave-v3-core/contracts/protocol/configuration/ACLManager.sol';
import {WETH9} from 'aave-v3-core/contracts/dependencies/weth/WETH9.sol';
import 'aave-v3-periphery/contracts/mocks/testnet-helpers/TestnetERC20.sol';
import 'aave-v3-core/contracts/protocol/pool/PoolConfigurator.sol';
import 'aave-v3-core/contracts/protocol/libraries/math/PercentageMath.sol';
import 'aave-v3-core/contracts/misc/AaveProtocolDataProvider.sol';
import {MarketReportUtils} from '../../src/deployments/contracts/utilities/MarketReportUtils.sol';

struct TestVars {
  string aTokenName;
  string aTokenSymbol;
  string variableDebtName;
  string variableDebtSymbol;
  string stableDebtName;
  string stableDebtSymbol;
  address rateStrategy;
  bytes interestRateData;
  bytes emptyParams;
  uint256 previousReservesLength;
}
struct TestReserveConfig {
  uint256 decimals;
  uint256 ltv;
  uint256 liquidationThreshold;
  uint256 liquidationBonus;
  uint256 reserveFactor;
  bool usageAsCollateralEnabled;
  bool borrowingEnabled;
  bool stableBorrowRateEnabled;
  bool isActive;
  bool isFrozen;
  bool isPaused;
}

contract BatchTestProcedures is Test, DeployUtils, FfiUtils, DefaultMarketInput {
  using PercentageMath for uint256;

  address poolAdmin;

  function deployCoreAndPeriphery(
    Roles memory roles,
    MarketConfig memory config,
    DeployFlags memory flags,
    MarketReport memory deployedContracts
  )
    internal
    returns (
      InitialReport memory initialReport,
      AaveV3GettersBatchOne.GettersReportBatchOne memory gettersReport1,
      PoolReport memory poolReport,
      PeripheryReport memory peripheryReport,
      ParaswapReport memory paraswapReport,
      AaveV3SetupBatch setupContract
    )
  {
    (setupContract, initialReport) = AaveV3BatchOrchestration._deploySetupContract(
      roles.marketOwner,
      roles,
      config,
      deployedContracts
    );

    gettersReport1 = AaveV3BatchOrchestration._deployGettersBatch1(
      initialReport.poolAddressesProvider,
      config.networkBaseTokenPriceInUsdProxyAggregator,
      config.marketReferenceCurrencyPriceInUsdProxyAggregator
    );

    poolReport = AaveV3BatchOrchestration._deployPoolImplementations(
      initialReport.poolAddressesProvider,
      flags
    );

    peripheryReport = AaveV3BatchOrchestration._deployPeripherals(
      roles,
      config,
      initialReport.poolAddressesProvider,
      address(setupContract)
    );

    paraswapReport = AaveV3BatchOrchestration._deployParaswapAdapters(
      roles,
      config,
      initialReport.poolAddressesProvider,
      peripheryReport.treasury
    );

    return (
      initialReport,
      gettersReport1,
      poolReport,
      peripheryReport,
      paraswapReport,
      setupContract
    );
  }

  function deployAndSetup(
    Roles memory roles,
    MarketConfig memory config,
    DeployFlags memory flags,
    MarketReport memory deployedContracts
  )
    internal
    returns (
      InitialReport memory initialReport,
      AaveV3GettersBatchOne.GettersReportBatchOne memory gettersReport1,
      AaveV3GettersBatchTwo.GettersReportBatchTwo memory gettersReport2,
      PoolReport memory poolReport,
      SetupReport memory setupReport,
      PeripheryReport memory peripheryReport,
      ParaswapReport memory paraswapReport,
      AaveV3SetupBatch setupContract
    )
  {
    (
      initialReport,
      gettersReport1,
      poolReport,
      peripheryReport,
      paraswapReport,
      setupContract
    ) = deployCoreAndPeriphery(roles, config, flags, deployedContracts);

    vm.prank(roles.marketOwner);
    setupReport = setupContract.setupAaveV3Market(
      roles,
      config,
      poolReport.poolImplementation,
      poolReport.poolConfiguratorImplementation,
      gettersReport1.protocolDataProvider,
      peripheryReport.aaveOracle,
      peripheryReport.rewardsControllerImplementation
    );

    gettersReport2 = AaveV3BatchOrchestration._deployGettersBatch2(
      setupReport.poolProxy,
      roles.poolAdmin,
      config.wrappedNativeToken,
      flags.l2
    );

    return (
      initialReport,
      gettersReport1,
      gettersReport2,
      poolReport,
      setupReport,
      peripheryReport,
      paraswapReport,
      setupContract
    );
  }

  function checkFullReport(DeployFlags memory flags, MarketReport memory r) internal pure {
    assertTrue(r.poolAddressesProviderRegistry != address(0), 'r.poolAddressesProviderRegistry');
    assertTrue(r.poolAddressesProvider != address(0), 'report.poolAddressesProvider');
    assertTrue(r.poolProxy != address(0), 'report.poolProxy');
    assertTrue(r.poolImplementation != address(0), 'report.poolImplementation');
    assertTrue(r.poolConfiguratorProxy != address(0), 'report.poolConfiguratorProxy');
    assertTrue(r.poolConfiguratorImplementation != address(0), 'r.poolConfiguratorImplementation');
    assertTrue(r.protocolDataProvider != address(0), 'report.protocolDataProvider');
    assertTrue(r.aaveOracle != address(0), 'report.aaveOracle');
    assertTrue(
      r.defaultInterestRateStrategyV2 != address(0),
      'report.defaultInterestRateStrategyV2'
    );
    assertTrue(r.aclManager != address(0), 'report.aclManager');
    assertTrue(r.treasury != address(0), 'report.treasury');
    assertTrue(r.proxyAdmin != address(0), 'report.proxyAdmin');
    assertTrue(r.treasuryImplementation != address(0), 'report.treasuryImplementation');
    assertTrue(r.wrappedTokenGateway != address(0), 'report.wrappedTokenGateway');
    assertTrue(r.walletBalanceProvider != address(0), 'report.walletBalanceProvider');
    assertTrue(r.uiIncentiveDataProvider != address(0), 'report.uiIncentiveDataProvider');
    assertTrue(r.uiPoolDataProvider != address(0), 'report.uiPoolDataProvider');
    assertTrue(r.paraSwapLiquiditySwapAdapter != address(0), 'report.paraSwapLiquiditySwapAdapter');
    assertTrue(r.paraSwapRepayAdapter != address(0), 'report.paraSwapRepayAdapter');
    assertTrue(r.paraSwapWithdrawSwapAdapter != address(0), 'report.paraSwapWithdrawSwapAdapter');
    assertTrue(r.aaveParaSwapFeeClaimer != address(0), 'report.aaveParaSwapFeeClaimer');

    if (flags.l2) {
      assertTrue(r.l2Encoder != address(0), 'report.l2Encoder');
    }

    assertTrue(r.aToken != address(0), 'report.aToken');
    assertTrue(r.variableDebtToken != address(0), 'report.variableDebtToken');
    assertTrue(r.stableDebtToken != address(0), 'report.stableDebtToken');
    assertTrue(r.emissionManager != address(0), 'report.emissionManager');
    assertTrue(
      r.rewardsControllerImplementation != address(0),
      'r.rewardsControllerImplementation'
    );
    assertTrue(r.rewardsControllerProxy != address(0), 'report.rewardsControllerProxy');
  }

  function deployAaveV3Testnet(
    address deployer,
    Roles memory roles,
    MarketConfig memory config,
    DeployFlags memory flags,
    MarketReport memory deployedContracts
  ) internal returns (MarketReport memory testReport) {
    detectFoundryLibrariesAndDelete();

    vm.startPrank(deployer);
    MarketReport memory deployReport = AaveV3BatchOrchestration.deployAaveV3(
      deployer,
      roles,
      config,
      flags,
      deployedContracts
    );
    vm.stopPrank();

    return deployReport;
  }

  function detectFoundryLibrariesAndDelete() internal {
    bool found = _librariesPathExists();

    if (found) {
      _deleteLibrariesPath();
      console.log(
        'TestnetProcedures: FOUNDRY_LIBRARIES was detected and removed. Please run again "make test" to deploy libraries with a fresh compilation.'
      );
      revert('Retry the "make test" command.');
    }
  }

  function _concatStr(string memory a, uint256 b) internal pure returns (string memory) {
    return string(abi.encodePacked(a, vm.toString(b)));
  }

  function _generateListingInput(
    uint256 listings,
    MarketReport memory r,
    address poolAdminUser
  ) internal returns (ConfiguratorInputTypes.InitReserveInput[] memory) {
    ConfiguratorInputTypes.InitReserveInput[]
      memory input = new ConfiguratorInputTypes.InitReserveInput[](listings);

    for (uint256 x; x < listings; ++x) {
      TestnetERC20 listingToken = new TestnetERC20(
        _concatStr('Token', x),
        _concatStr('T', x),
        uint8(10 + x),
        poolAdminUser
      );
      TestVars memory t;
      t.aTokenName = _concatStr('AToken ', x);
      t.aTokenName = _concatStr('a ', x);
      t.variableDebtName = _concatStr('Variable Debt Misc', x);
      t.variableDebtSymbol = _concatStr('varDebtMISC ', x);
      t.stableDebtName = _concatStr('Stable Debt Misc ', x);
      t.stableDebtSymbol = _concatStr('stableDebtMISC ', x);
      t.rateStrategy = r.defaultInterestRateStrategyV2;
      t.interestRateData = abi.encode(
        IDefaultInterestRateStrategyV2.InterestRateData({
          optimalUsageRatio: 80_00,
          baseVariableBorrowRate: 1_00,
          variableRateSlope1: 4_00,
          variableRateSlope2: 60_00
        })
      );

      input[x] = ConfiguratorInputTypes.InitReserveInput(
        r.aToken,
        r.stableDebtToken,
        r.variableDebtToken,
        listingToken.decimals(),
        true,
        t.rateStrategy,
        address(listingToken),
        r.treasury,
        r.rewardsControllerProxy,
        t.aTokenName,
        t.aTokenSymbol,
        t.variableDebtName,
        t.variableDebtSymbol,
        t.stableDebtName,
        t.stableDebtSymbol,
        t.emptyParams,
        t.interestRateData
      );
    }

    return input;
  }
}
