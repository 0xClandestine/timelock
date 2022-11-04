// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Timelock.sol";

contract MockTarget {

    bool public bar;

    function foo() public {
        bar = true;
    }
}

contract TimelockTest is Test {
    Timelock public timelock;
    MockTarget public target;

    function setUp() public {
        timelock = new Timelock(14 days, 1 days, 30 days);
        target = new MockTarget();
    }

    function testQueue() public {

        bytes memory data = bytes(abi.encode(MockTarget.foo.selector));

        Payload memory payload = Payload(
            payable(address(target)), 0, block.timestamp + timelock.MINIMUM_DELAY(), data
        );

        Payload memory delayTooShort = Payload(
            payable(address(target)), 0, block.timestamp + timelock.MINIMUM_DELAY() - 1, data
        );

        Payload memory delayTooLong = Payload(
            payable(address(target)), 0, block.timestamp + timelock.MAXIMUM_DELAY() + 1, data
        );

        timelock.queue(payload);

        // Ensure payload hash is marked as queued.
        assertTrue(timelock.queued(keccak256(abi.encode(payload))));

        // Ensure payload cannot be queued twice at a single time.
        vm.expectRevert(Timelock.PAYLOAD_ALREADY_QUEUED.selector);
        timelock.queue(payload);

        // Ensure payload eta satisfies MINIMUM_DELAY
        vm.expectRevert(Timelock.MIN_DELAY_NOT_SATISFIED.selector);
        timelock.queue(delayTooShort);

        // Ensure payload eta satisfies MINIMUM_DELAY
        vm.expectRevert(Timelock.MAX_DELAY_NOT_SATISFIED.selector);
        timelock.queue(delayTooLong);
    }

    function testCancel() public {

        bytes memory data = bytes(abi.encode(MockTarget.foo.selector));

        Payload memory payload = Payload(
            payable(address(target)), 0, block.timestamp + timelock.MINIMUM_DELAY(), data
        );

        timelock.queue(payload);

        assertTrue(timelock.queued(keccak256(abi.encode(payload))));

        timelock.cancel(payload);
        
        // Ensure payload is no longer marked as queued.
        assertTrue(!timelock.queued(keccak256(abi.encode(payload))));
    }

    function testExecute() public {

        bytes memory data = bytes(abi.encode(MockTarget.foo.selector));

        uint256 eta = block.timestamp + timelock.MINIMUM_DELAY();

        Payload memory payload = Payload(payable(address(target)), 0, eta, data);

        timelock.queue(payload);        

        // Ensure payload cannot be executed before delay has elapsed.
        vm.expectRevert(Timelock.PAYLOAD_IS_NOT_READY.selector);
        timelock.execute(payload);

        // Ensure payload cannot be executed after grace period has elapsed.
        vm.warp(eta + timelock.GRACE_PERIOD() + 1);
        vm.expectRevert(Timelock.PAYLOAD_HAS_EXPIRED.selector);
        timelock.execute(payload);

        // Ensure payload calls target contract properly.
        vm.warp(eta);
        timelock.execute(payload);
        assertTrue(target.bar());

        // Ensure payload cannot be replayed.
        vm.expectRevert(Timelock.PAYLOAD_IS_NOT_QUEUED.selector);
        timelock.execute(payload);
    }
}
