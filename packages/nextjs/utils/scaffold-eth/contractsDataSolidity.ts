import { useTargetNetwork } from "~~/hooks/scaffold-eth";
import { GenericContractsDeclaration, contracts } from "~~/utils/scaffold-eth/contract";

const DEFAULT_ALL_CONTRACTS: GenericContractsDeclaration[number] = {};

/**
 * Hook to get only Solidity contracts (contracts with "-solidity" suffix)
 * This filters the contracts to show only those deployed via Solidity deploy.sh
 */
export function useSolidityContracts() {
  const { targetNetwork } = useTargetNetwork();
  const allContractsData = contracts?.[targetNetwork.id] || DEFAULT_ALL_CONTRACTS;

  // Filter contracts to only those with "-solidity" suffix
  const solidityContracts: GenericContractsDeclaration[number] = {};

  Object.keys(allContractsData).forEach(contractName => {
    if (contractName.endsWith("-solidity")) {
      solidityContracts[contractName] = allContractsData[contractName];
    }
  });

  return solidityContracts;
}
