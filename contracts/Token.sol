// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import "./abstracts/BaseContract.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";


contract Token is BaseContract, ERC20Upgradeable {
    using SafeMath for uint256;

    /**
     * Contract initializer.
     * @dev This intializes all the parent contracts.
     */
    function initialize(
        address router_,
        uint256 reflectionFee_,
        uint256 initialMintAmount_
    ) 
        initializer public
    {
        __BaseContract_init();
        __ERC20_init("reflection token", "$TOKEN");

        router = IUniswapV2Router02(router_);
        pair = IUniswapV2Factory(router.factory()).createPair(
            router.WETH(),
            address(this)
        );

        feeDenominator = 1000;
        dividendsPerShareAccuracyFactor = 10 **18;

        isDividendExempt[msg.sender] = true;
        isDividendExempt[router_] = true;
        isDividendExempt[pair] = true;
        isDividendExempt[address(this)] = true;
        isDividendExempt[address(0)] = true;

        reflectionFee = reflectionFee_;

        super._mint(msg.sender, initialMintAmount_);
    }

    mapping (address => bool) isDividendExempt;

    uint256 reflectionFee;
    uint256 feeDenominator;

    IUniswapV2Router02 public router;
    address public pair;

    //For Reflecition
    struct Share {
        uint256 amount;
        uint256 totalExcluded;
        uint256 totalRealised;
    }

    address[] shareholders;
    mapping(address => uint256) shareholderIndexes;
    mapping(address => uint256) totalRewardsDistributed;
    mapping(address => Share) shares;

    uint256 totalShares;
    uint256 dividendsPerShare;
    uint256 dividendsPerShareAccuracyFactor;

    function mint(address to, uint256 amount) external onlyOwner
    {
        super._mint(to, amount);
    }

    function burn(address account, uint256 amount) external onlyOwner
    {
        super._burn(account, amount);
    }

    /**
     * _transfer override for taxes.
     * @param from From address.
     * @param to To address.
     * @param amount Transfer amount.
     */
    function _transfer(address from, address to, uint256 amount) internal override
    {

        uint256 _feeAmount = amount.mul(reflectionFee).div(feeDenominator);
        super._transfer(from, address(this), _feeAmount);
        super._transfer(from, to, amount.sub(_feeAmount));

        if(!isDividendExempt[from]) _setShare(from, balanceOf(from));
        if(!isDividendExempt[to]) _setShare(to, balanceOf(to));

        updateDivendensPerShare(_feeAmount);

    }

    function setIsDividendExempt(address holder, bool exempt) external onlyOwner 
    {
        require(holder != address(this) && holder != pair);
        isDividendExempt[holder] = exempt;
        if(exempt){
            _setShare(holder, 0);
        }else{
            _setShare(holder, balanceOf(holder));
        }
    }

    function _setShare(address shareholder, uint256 amount) internal 
    {
        if (shares[shareholder].amount > 0) {
            distributeDividend(shareholder);
        }

        if (amount > 0 && shares[shareholder].amount == 0) {
            addShareholder(shareholder);
        } else if (amount == 0 && shares[shareholder].amount > 0) {
            removeShareholder(shareholder);
        }

        totalShares = totalShares.add(amount).sub(
            shares[shareholder].amount
        );
        shares[shareholder].amount = amount;
        shares[shareholder].totalExcluded = getCumulativeDividends(
            shares[shareholder].amount
        );
    }

    function updateDivendensPerShare(uint256 amount) internal {
        if (totalShares == 0) return;
        dividendsPerShare = dividendsPerShare.add(
            dividendsPerShareAccuracyFactor.mul(amount).div(totalShares)
        );
    }

    function distributeDividend(address shareholder) internal {
        if (shares[shareholder].amount == 0) {
            return;
        }

        uint256 amount = getUnpaidEarnings(shareholder);

        if (amount > 0) {
            super._transfer(address(this), shareholder, amount);
            shares[shareholder].totalRealised = shares[shareholder]
                .totalRealised
                .add(amount);
            shares[shareholder].totalExcluded = getCumulativeDividends(
                shares[shareholder].amount
            );
        }
    }

    function claimDividend() external {
        distributeDividend(msg.sender);
    }

    function getUnpaidEarnings(address shareholder)
        public
        view
        returns (uint256)
    {
        if (shares[shareholder].amount == 0) {
            return 0;
        }

        uint256 shareholderTotalDividends = getCumulativeDividends(
            shares[shareholder].amount
        );
        uint256 shareholderTotalExcluded = shares[shareholder].totalExcluded;

        if (shareholderTotalDividends <= shareholderTotalExcluded) {
            return 0;
        }

        return shareholderTotalDividends.sub(shareholderTotalExcluded);
    }

    function getCumulativeDividends(uint256 share)
        internal
        view
        returns (uint256)
    {
        return share.mul(dividendsPerShare).div(dividendsPerShareAccuracyFactor);
    }

    function addShareholder(address shareholder) internal {
        shareholderIndexes[shareholder] = shareholders.length;
        shareholders.push(shareholder);
    }

    function removeShareholder(address shareholder) internal {
        shareholders[shareholderIndexes[shareholder]] = shareholders[
            shareholders.length - 1
        ];
        shareholderIndexes[
            shareholders[shareholders.length - 1]
        ] = shareholderIndexes[shareholder];
        shareholders.pop();
    }

    function withdraw() external onlyOwner {
        super._transfer(address(this), msg.sender, balanceOf(address(this)));
    }
}