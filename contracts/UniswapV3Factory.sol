// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './interfaces/IUniswapV3Factory.sol';

import './UniswapV3PoolDeployer.sol';
import './NoDelegateCall.sol';

import './UniswapV3Pool.sol';

/// @title Canonical Uniswap V3 factory
/// @notice Deploys Uniswap V3 pools and manages ownership and control over pool protocol fees
contract UniswapV3Factory is IUniswapV3Factory, UniswapV3PoolDeployer, NoDelegateCall {
    /// @inheritdoc IUniswapV3Factory
    /// public类型的状态变量owner重写IUniswapV3Factory中的owner()函数
    /// 因为owner()函数具有external的可见性，且owner对应的getter()函数的参数和返回值的类型和owner()函数一致
    address public override owner; 

    /// @inheritdoc IUniswapV3Factory
    /// 重写IUniswapV3Factory中的feeAmountTickSpacing()函数
    /// 前一个参数表示fee，后一个表示tickSpacing
    mapping(uint24 => int24) public override feeAmountTickSpacing;
    /// @inheritdoc IUniswapV3Factory
    mapping(address => mapping(address => mapping(uint24 => address))) public override getPool;

/// owner部署UniswapV3Factory合约，预先设置fee和tickSpacing的三个映射关系，该合约全局唯一
/// 其他用户可以调用该UniswapV3Factory合约中的createPool函数，从而部署一个UniswapV3Pool合约，返回一个pool地址
    constructor() {
        owner = msg.sender;
        emit OwnerChanged(address(0), msg.sender);

        feeAmountTickSpacing[500] = 10;
        emit FeeAmountEnabled(500, 10);
        feeAmountTickSpacing[3000] = 60;
        emit FeeAmountEnabled(3000, 60);
        feeAmountTickSpacing[10000] = 200;
        emit FeeAmountEnabled(10000, 200);
    }

    /// @inheritdoc IUniswapV3Factory
    /// fee 只能是上述的500 3000 10000
    /// 用户调用该函数，只需要输入token0Addr、token1Addr、在池中交换收取的费用fee，在函数中会先对token0Addr、token1Addr进行从小到大的排序，
    /// 之后根据UniswapV3Factory合约地址、token0、token1、fee、tickSpacing、salt值、UniswapV3Pool合约字节码, 创建一个UniswapV3Pool合约，返回pool地址
    /// 同一个token0->token1->fee代表的pool只能被创建一次
    /// 该pool中的流动性max liquidity 将根据tickSpacing 在Tick.sol中进行计算，计算方法是简单的加减乘除
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external override noDelegateCall returns (address pool) {
        require(tokenA != tokenB);
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0));
        int24 tickSpacing = feeAmountTickSpacing[fee];
        require(tickSpacing != 0);
        require(getPool[token0][token1][fee] == address(0)); //需要该pool还没有被创建过
        pool = deploy(address(this), token0, token1, fee, tickSpacing);
        getPool[token0][token1][fee] = pool;
        // populate mapping in the reverse direction, deliberate choice to avoid the cost of comparing addresses
        // 这个显得多余？上面已经进行过地址比较了。。。
        getPool[token1][token0][fee] = pool;
        emit PoolCreated(token0, token1, fee, tickSpacing, pool);
    }

    /// @inheritdoc IUniswapV3Factory
    /// 由UniswapV3Factory合约的原owner调用
    function setOwner(address _owner) external override {
        require(msg.sender == owner);
        emit OwnerChanged(owner, _owner);
        owner = _owner;
    }

    /// @inheritdoc IUniswapV3Factory
    /// 由UniswapV3Factory合约的owner调用，增加一个fee->tickSpacing的映射关系
    /// 为什么tickSpacing需要小于16384??
    /// 16384等于2的14次方
    function enableFeeAmount(uint24 fee, int24 tickSpacing) public override {
        require(msg.sender == owner);
        require(fee < 1000000);
        // tick spacing is capped at 16384 to prevent the situation where tickSpacing is so large that
        // TickBitmap#nextInitializedTickWithinOneWord overflows int24 container from a valid tick
        // 16384 ticks represents a >5x price change with ticks of 1 bips
        // tickSpacing的上限为16384，以防止tickSpacing过大从而导致TickBitmap＃nextInitializedTickWithinOneWord从有效的tick中的int24容器溢出
        // 16384的ticks表示大于5倍的价格变动（1点子的刻度线）
        require(tickSpacing > 0 && tickSpacing < 16384);
        require(feeAmountTickSpacing[fee] == 0);

        feeAmountTickSpacing[fee] = tickSpacing;
        emit FeeAmountEnabled(fee, tickSpacing);
    }
}
