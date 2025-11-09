"use client";

import { useEffect, useMemo } from "react";
import { useSessionStorage } from "usehooks-ts";
import { useTheme } from "next-themes";
import { BarsArrowUpIcon } from "@heroicons/react/20/solid";
import { ContractUI } from "~~/app/debugsolidity/_components/contract";
import { ContractName, GenericContract } from "~~/utils/scaffold-eth/contract";
import { useSolidityContracts } from "~~/utils/scaffold-eth/contractsDataSolidity";

const selectedContractStorageKey = "scaffoldEth2.selectedSolidityContract";

export function DebugContractsSolidity() {
  const contractsData = useSolidityContracts();
  const { resolvedTheme } = useTheme();
  const isDarkMode = useMemo(() => resolvedTheme === "dark", [resolvedTheme]);
  const contractNames = useMemo(
    () =>
      Object.keys(contractsData).sort((a, b) => {
        return a.localeCompare(b, undefined, { numeric: true, sensitivity: "base" });
      }) as ContractName[],
    [contractsData],
  );

  const [selectedContract, setSelectedContract] = useSessionStorage<ContractName>(
    selectedContractStorageKey,
    contractNames[0],
    { initializeWithValue: false },
  );

  useEffect(() => {
    if (!contractNames.includes(selectedContract)) {
      setSelectedContract(contractNames[0]);
    }
  }, [contractNames, selectedContract, setSelectedContract]);

  return (
    <div className="flex flex-col gap-y-6 lg:gap-y-8 py-8 lg:py-12 justify-center items-center">
      {contractNames.length === 0 ? (
        <p className="text-3xl mt-14">No Solidity contracts found!</p>
      ) : (
        <>
          {contractNames.length > 1 && (
            <div className="flex flex-row gap-2 w-full max-w-7xl pb-1 px-6 lg:px-10 flex-wrap">
              {contractNames.map(contractName => {
                const contractNameStr = String(contractName);
                return (
                  <button
                    className="contract-tab-button"
                    key={contractNameStr}
                    onClick={() => setSelectedContract(contractName)}
                    style={{
                      backgroundColor:
                        contractName === selectedContract
                          ? "rgba(227, 6, 110, 1)"
                          : isDarkMode
                            ? "transparent"
                            : "white",
                      color: contractName === selectedContract ? "white" : isDarkMode ? "white" : "black",
                      border:
                        contractName === selectedContract
                          ? "none"
                          : isDarkMode
                            ? "1px solid rgba(255, 255, 255, 0.20)"
                            : "1px solid rgba(0, 0, 0, 0.1)",
                    }}
                  >
                    {contractNameStr}
                    {(contractsData[contractName] as GenericContract)?.external && (
                      <span className="tooltip tooltip-top tooltip-accent" data-tip="External contract">
                        <BarsArrowUpIcon className="h-4 w-4 cursor-pointer" />
                      </span>
                    )}
                  </button>
                );
              })}
            </div>
          )}
          {contractNames.map(contractName => {
            const contractNameStr = String(contractName);
            return (
              <ContractUI
                key={contractNameStr}
                contractName={contractName}
                className={contractName === selectedContract ? "" : "hidden"}
              />
            );
          })}
        </>
      )}
    </div>
  );
}
