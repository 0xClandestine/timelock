// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "solbase/auth/Owned.sol";

struct Payload {
    address payable target;
    uint256 value;
    uint256 eta;
    bytes data;
}

contract Timelock is Owned(msg.sender) {

    receive() external payable {}

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event PayloadQueued(address target, uint256 value, uint256 eta, bytes data);
    event PayloadCancelled(address target, uint256 value, uint256 eta, bytes data);
    event PayloadExecuted(address target, uint256 value, uint256 eta, bytes data);

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error MIN_DELAY_NOT_SATISFIED();
    error MAX_DELAY_NOT_SATISFIED();
    error PAYLOAD_ALREADY_QUEUED();
    error PAYLOAD_IS_NOT_QUEUED();
    error PAYLOAD_IS_NOT_READY();
    error PAYLOAD_EXECUTION_FAILED();
    error PAYLOAD_HAS_EXPIRED();

    /// -----------------------------------------------------------------------
    /// Mutables
    /// -----------------------------------------------------------------------

    mapping(bytes32 => bool) public queued;

    /// -----------------------------------------------------------------------
    /// Immutables
    /// -----------------------------------------------------------------------

    uint256 public immutable GRACE_PERIOD;
    uint256 public immutable MINIMUM_DELAY;
    uint256 public immutable MAXIMUM_DELAY;

    constructor(uint256 graceDelay, uint256 minDelay, uint256 maxDelay) {
        GRACE_PERIOD = graceDelay;
        MINIMUM_DELAY = minDelay;
        MAXIMUM_DELAY = maxDelay;
    }

    /// -----------------------------------------------------------------------
    /// Timelock Logic
    /// -----------------------------------------------------------------------

    function queue(Payload memory payload) external onlyOwner payable virtual {
        unchecked {
            uint256 timeDelta = payload.eta - block.timestamp;
            if (timeDelta < MINIMUM_DELAY) revert MIN_DELAY_NOT_SATISFIED();
            if (timeDelta > MAXIMUM_DELAY) revert MAX_DELAY_NOT_SATISFIED();
            bytes32 payloadHash = keccak256(abi.encode(payload));
            if (queued[payloadHash]) revert PAYLOAD_ALREADY_QUEUED();
            queued[payloadHash] = true;
            emit PayloadQueued(payload.target, payload.value, payload.eta, payload.data);
        }
    }

    function cancel(Payload memory payload) external onlyOwner virtual {
        bytes32 payloadHash = keccak256(abi.encode(payload));
        if (!queued[payloadHash]) revert PAYLOAD_IS_NOT_QUEUED();
        delete queued[payloadHash];
        emit PayloadCancelled(payload.target, payload.value, payload.eta, payload.data);
    }

    function execute(Payload memory payload) external onlyOwner virtual returns (bytes memory) {
        bytes32 payloadHash = keccak256(abi.encode(payload));
        if (block.timestamp < payload.eta) revert PAYLOAD_IS_NOT_READY();
        if (block.timestamp > payload.eta + GRACE_PERIOD) revert PAYLOAD_HAS_EXPIRED();
        if (!queued[payloadHash]) revert PAYLOAD_IS_NOT_QUEUED();
        (bool success, bytes memory returnData) = payload.target.call{value: payload.value}(payload.data);
        if (!success) revert PAYLOAD_EXECUTION_FAILED();
        delete queued[payloadHash];
        emit PayloadExecuted(payload.target, payload.value, payload.eta, payload.data);
        return returnData;
    }
}
