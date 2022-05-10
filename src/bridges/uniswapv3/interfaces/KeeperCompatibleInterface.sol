pragma solidity >=0.6.10 <=0.8.10;

interface KeeperCompatibleInterface {

  /*
   * @notice method that is simulated by the keepers to see if any work actually
   * needs to be performed. This method does does not actually need to be
   * executable, and since it is only ever simulated it can consume lots of gas.
   * @dev To ensure that it is never called, you may want to add the
   * cannotExecute modifier from KeeperBase to your implementation of this
   * method.
   * @return success boolean to indicate whether the keeper should call
   * performUpkeep or not.
   * @return success bytes that the keeper should call performUpkeep with, if
   * upkeep is needed.
   */
  function checkUpkeep(
    bytes calldata data
  )
    external
    returns (
      bool success,
      bytes memory dynamicData
    );
  function performUpkeep(
    bytes calldata dynamicData
  ) external;
}