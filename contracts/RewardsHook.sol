// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./IMarketHooks.sol";
import "./IDonatable.sol";
import "./IRewardable.sol";

contract RewardsHook is IMarketHooks, IRewardable, IDonatable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct RewardInfo {
        uint256 rate; // tokens per second
        uint256 end;
        uint256 lastUpdate;
        uint256 accRewardPerLiability; // scaled by 1e18
    }

    struct UserInfo {
        uint256 userRewardPerLiabilityPaid;
        uint256 rewardsOwed;
    }

    mapping(address => RewardInfo) public rewardData; // token => reward info
    mapping(address => mapping(address => UserInfo)) public userInfo; // user => token => info
    mapping(address => bool) public isRewardToken;
    address[] public rewardTokens;
    address public market;

    function _updateReward(
        address account,
        address token,
        uint256 liabilities,
        uint256 totalLiabilities
    ) internal {
        RewardInfo storage r = rewardData[token];
        UserInfo storage u = userInfo[token][account];

        uint256 currentTime = block.timestamp;
        uint256 timeDelta = _min(currentTime, r.end) - r.lastUpdate;
        uint256 reward = timeDelta * r.rate;
        r.accRewardPerLiability += (reward * 1e18) / totalLiabilities;
        r.lastUpdate = currentTime;

        if (account != address(0)) {
            uint256 delta = r.accRewardPerLiability -
                u.userRewardPerLiabilityPaid;
            uint256 accrued = (liabilities * delta) / 1e18;

            u.userRewardPerLiabilityPaid = r.accRewardPerLiability;
            u.rewardsOwed += accrued;
        }
    }

    function donate(
        address token,
        uint256 amount,
        uint40 window
    ) external override {
        require(amount > 0 && window > 0, "Invalid input");
        RewardInfo storage r = rewardData[token];
        require(block.timestamp >= r.end, "Previous distribution still active");

        _updateReward(
            address(0),
            token,
            0,
            IMarket(market).getTotalLiability()
        );

        if (!isRewardToken[token]) {
            isRewardToken[token] = true;
            rewardTokens.push(token);
        }

        if (block.timestamp >= r.end) {
            r.rate = (amount * 1e18) / window;
        } else {
            uint256 remaining = r.end - block.timestamp;
            uint256 leftover = (remaining * r.rate) / 1e18;
            uint256 newAmount = amount + leftover;
            r.rate = (newAmount * 1e18) / window;
        }

        r.end = block.timestamp + window;
        r.lastUpdate = block.timestamp;

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit Donate(
            msg.sender,
            token,
            amount,
            r.rate,
            uint40(block.timestamp),
            uint40(r.end)
        );
    }

    function getRewardTokens()
        external
        view
        override
        returns (address[] memory)
    {
        return rewardTokens;
    }

    function claimRewards(
        address account,
        address[] calldata tokens,
        uint256[] calldata /* amounts */
    ) external override nonReentrant returns (uint256[] memory claimed) {
        require(tokens.length > 0, "No tokens");
        claimed = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            RewardInfo storage r = rewardData[token];

            _updateReward(
                account,
                token,
                IMarket(market).getUserLiability(account),
                IMarket(market).getTotalLiability()
            );

            UserInfo storage u = userInfo[account][token];
            uint256 rewardsOwed = u.rewardsOwed;

            if (rewardsOwed > 0) {
                u.rewardsOwed = 0;
                IERC20(token).safeTransfer(account, rewardsOwed);
                claimed[i] = rewardsOwed;
                emit ClaimRewards(
                    account,
                    token,
                    account,
                    rewardsOwed,
                    msg.sender
                );
            }
        }
    }

    function getClaimableRewards(
        address account
    )
        external
        view
        override
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        tokens = rewardTokens;
        amounts = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            RewardInfo memory r = rewardData[token];
            UserInfo memory u = userInfo[token][account];

            uint256 currentTime = block.timestamp;
            uint256 timeDelta = _min(currentTime, r.end) - r.lastUpdate;
            uint256 reward = timeDelta * r.rate;
            uint256 totalLiabilities = IMarket(market).getTotalLiability();
            uint256 userBorrows = IMarket(market).getUserLiability(account);

            uint256 rewardPerLiability = r.accRewardPerLiability +
                (reward * 1e18) /
                totalLiabilities;

            uint256 delta = rewardPerLiability - u.userRewardPerLiabilityPaid;
            uint256 accrued = (userBorrows * delta) / 1e18;
            amounts[i] = u.rewardsOwed + accrued;
        }
    }

    function beforeBorrow(
        BorrowHookParams memory params
    ) external override returns (bytes memory) {
        _updateLiability(
            params.account,
            params.amount,
            params.liabilities,
            params.totalLiabilities
        );
        return "";
    }

    function afterBorrow(
        BorrowHookParams memory params,
        bytes memory
    ) external override {}

    function beforeRepay(
        RepayHookParams memory params
    ) external override returns (bytes memory) {
        _updateLiability(
            params.account,
            params.amount,
            params.liabilities,
            params.totalLiabilities
        );
        return "";
    }

    function afterRepay(
        RepayHookParams memory params,
        bytes memory
    ) external override {}

    function _updateLiability(
        address account,
        uint256 borrowAmount,
        uint256 liabilities,
        uint256 totalLiabilities
    ) internal {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            _updateReward(account, token, liabilities, totalLiabilities);
        }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

interface IMarket {
    function getTotalLiability() external view returns (uint256);
    function getUserLiability(address _account) external view returns (uint256);
}
