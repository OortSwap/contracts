// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract MultiSigPeriodicTimeLock {
    using SafeERC20 for IERC20;
    using SafeMath for  uint256;

    IERC20 public  token;
    address public beneficiary;
    uint256 public releaseTime;
    address[] public requiredSignatories;
    uint256 public period;

    enum Action {
      RELEASE,
      SET_BENEFICIARY
    }

    mapping(address => mapping(Action => bool)) public approvals;

    constructor(
      address _beneficiary,
      uint256 _periodInSeconds,
      address[] memory _requiredSignatories
    ) {
      beneficiary = _beneficiary;
      period = _periodInSeconds;
      releaseTime = block.timestamp + period;
      for (uint256 i = 0; i < _requiredSignatories.length; i++) {
        requiredSignatories.push(_requiredSignatories[i]);
      }
    }

    function setTokenAddr(IERC20 _token) external signatoryOnly  {
        token = IERC20(_token);
    }

    function lock() public signatoryOnly afterTimeElapsed {
      releaseTime = block.timestamp + period;
    }

    function approve(Action action) external signatoryOnly {
      approvals[msg.sender][action] = true;
    }

    function setBeneficiary(address addr) external signatoryOnly requireApprovalFor(Action.SET_BENEFICIARY) {
      beneficiary = addr;
    }

    function release() external signatoryOnly afterTimeElapsed requireApprovalFor(Action.RELEASE) {
      uint256 amount = token.balanceOf(address(this));
      require(amount > 0, "No tokens to release");
      uint256 releaseAmount = amount.div(2);
      require(amount >= releaseAmount, "No enough tokens to release");

      token.safeTransfer(beneficiary, releaseAmount);
      lock();
    }

    modifier signatoryOnly() {
      bool found = false;
      for (uint256 i = 0; i < requiredSignatories.length; i++) {
        if (requiredSignatories[i] == msg.sender) {
          found = true;
        }
      }
      require(found, "Not signatory");
      _;
    }

    modifier requireApprovalFor(Action action) {
      uint256 approvalsCount = 0;

      for (uint256 i = 0; i < requiredSignatories.length; i++) {
        if(approvals[requiredSignatories[i]][action]) {
          approvalsCount++;
        }

        approvals[requiredSignatories[i]][action] = false;
      }

      require(approvalsCount >= requiredSignatories.length.div(2),"Signatory has not enough approved");
      _;
    }
    
    modifier afterTimeElapsed {
      require(block.timestamp >= releaseTime, "Current time is before release time");
      _;
    }
}