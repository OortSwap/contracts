// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./libraries/SafeMath.sol";
import "./MultiSigWallet.sol";


contract MultiSigWalletWithTimeLock is
    MultiSigWallet
{
    using SafeMath for uint256;

    event ConfirmationTimeSet(uint256 indexed transactionId, uint256 confirmationTime);
    event TimeLockChange(uint256 secondsTimeLocked);

    uint256 public secondsTimeLocked;

    mapping (uint256 => uint256) public confirmationTimes;

    modifier fullyConfirmed(uint256 transactionId) {
        require(
            isConfirmed(transactionId),
            "TX_NOT_FULLY_CONFIRMED"
        );
        _;
    }

    modifier pastTimeLock(uint256 transactionId) {
        require(
            block.timestamp >= confirmationTimes[transactionId].add(secondsTimeLocked),
            "TIME_LOCK_INCOMPLETE"
        );
        _;
    }

    /// @dev Contract constructor sets initial owners, required number of confirmations, and time lock.
    /// @param _owners List of initial owners.
    /// @param _required Number of required confirmations.
    /// @param _secondsTimeLocked Duration needed after a transaction is confirmed and before it becomes executable, in seconds.
    constructor (
        address[] memory _owners,
        uint256 _required,
        uint256 _secondsTimeLocked
    )
        public
        MultiSigWallet(_owners, _required)
    {
        secondsTimeLocked = _secondsTimeLocked;
    }

    /// @dev Changes the duration of the time lock for transactions.
    /// @param _secondsTimeLocked Duration needed after a transaction is confirmed and before it becomes executable, in seconds.
    function changeTimeLock(uint256 _secondsTimeLocked)
        public
        onlyWallet
    {
        secondsTimeLocked = _secondsTimeLocked;
        emit TimeLockChange(_secondsTimeLocked);
    }

    /// @dev Allows an owner to confirm a transaction.
    /// @param transactionId Transaction ID.
    function confirmTransaction(uint256 transactionId)
        public
        override
        ownerExists(msg.sender)
        transactionExists(transactionId)
        notConfirmed(transactionId, msg.sender)
    {
        bool isTxFullyConfirmedBeforeConfirmation = isConfirmed(transactionId);

        confirmations[transactionId][msg.sender] = true;
        emit Confirmation(msg.sender, transactionId);

        if (!isTxFullyConfirmedBeforeConfirmation && isConfirmed(transactionId)) {
            _setConfirmationTime(transactionId, block.timestamp);
        }
    }

    /// @dev Allows anyone to execute a confirmed transaction.
    /// @param transactionId Transaction ID.
    function executeTransaction(uint256 transactionId)
        public
        override
        notExecuted(transactionId)
        fullyConfirmed(transactionId)
        pastTimeLock(transactionId)
    {
        Transaction storage txn = transactions[transactionId];
        txn.executed = true;
        if (external_call(txn.destination, txn.value, txn.data.length, txn.data)) {
            emit Execution(transactionId);
        } else {
            emit ExecutionFailure(transactionId);
            txn.executed = false;
        }
    }

    /// @dev Sets the time of when a submission first passed.
    function _setConfirmationTime(uint256 transactionId, uint256 confirmationTime)
        internal
    {
        confirmationTimes[transactionId] = confirmationTime;
        emit ConfirmationTimeSet(transactionId, confirmationTime);
    }
}
