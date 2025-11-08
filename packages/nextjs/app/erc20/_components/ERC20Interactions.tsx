"use client";

import { useMemo, useReducer, useState } from "react";
import { useTheme } from "next-themes";
import { ContractReadMethods } from "~~/app/debug/_components/contract/ContractReadMethods";
import { ContractWriteMethods } from "~~/app/debug/_components/contract/ContractWriteMethods";
import { Address, Balance } from "~~/components/scaffold-eth";
import { useTargetNetwork } from "~~/hooks/scaffold-eth/useTargetNetwork";
import { BalanceOfDisplay } from "./BalanceOfDisplay";
import requiredContracts from "~~/contracts/requiredContracts ";

const CONTRACT_NAME = "erc20-example";

export const ERC20Interactions = () => {
  const [activeTab, setActiveTab] = useState("read");
  const [refreshDisplayVariables, triggerRefreshDisplayVariables] = useReducer(value => !value, false);
  const { targetNetwork } = useTargetNetwork();
  const { resolvedTheme } = useTheme();
  const isDarkMode = useMemo(() => resolvedTheme === "dark", [resolvedTheme]);

  // Get contract data from requiredContracts.ts
  const contractData = useMemo(() => {
    const chainId = targetNetwork.id.toString();
    const contracts = requiredContracts as any;
    return contracts[chainId]?.[CONTRACT_NAME];
  }, [targetNetwork.id]);

  const tabs = [
    { id: "read", label: "Read" },
    { id: "write", label: "Write" },
  ];

  if (!contractData) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <p className="text-3xl">
          {`Contract "${CONTRACT_NAME}" not found for chain "${targetNetwork.name}" (${targetNetwork.id})!`}
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-y-6 lg:gap-y-8 py-8 lg:py-12 justify-center items-center">
      <div className="grid grid-cols-1 lg:grid-cols-6 px-6 lg:px-10 lg:gap-12 w-full max-w-7xl my-0">
        <div className="col-span-5 grid grid-cols-1 lg:grid-cols-3 gap-8 lg:gap-10">
          <div className="col-span-1 flex flex-col">
            <div
              className="mb-6 rounded-2xl p-6"
              style={{
                backgroundColor: isDarkMode ? "rgba(2, 2, 2, 0.40)" : "transparent",
                border: isDarkMode ? "1px solid rgba(255, 255, 255, 0.20)" : "1px solid rgba(0, 0, 0, 0.1)",
                backdropFilter: isDarkMode ? "blur(25px)" : "none",
              }}
            >
              <div className="flex flex-col gap-4 w-full">
                {/* Contract Title */}
                <div
                  style={{
                    color: isDarkMode ? "#30B4ED" : "#30B4ED",
                    fontSize: "1.25rem",
                    fontWeight: "bold",
                  }}
                >
                  {CONTRACT_NAME}
                </div>

                <Address address={contractData.address} onlyEnsOrAddress />

                {/* Balance */}
                <div className="flex items-center gap-2">
                  <span
                    style={{
                      color: isDarkMode ? "white" : "black",
                      fontWeight: "bold",
                    }}
                  >
                    Balance:
                  </span>
                  <Balance address={contractData.address} className="px-0 h-1.5 min-h-[0.375rem]" />
                </div>

                {/* Network */}
                {targetNetwork && (
                  <div className="flex items-center gap-2">
                    <span
                      style={{
                        color: isDarkMode ? "white" : "black",
                        fontWeight: "bold",
                      }}
                    >
                      Network:
                    </span>
                    <span
                      style={{
                        color: isDarkMode ? "#FF50A2" : "rgba(227, 6, 110, 1)",
                        fontSize: "14px",
                      }}
                    >
                      {targetNetwork.name}
                    </span>
                  </div>
                )}
              </div>
            </div>

            {/* BalanceOf Display */}
            <div
              className="rounded-xl px-6 lg:px-8 py-4"
              style={{
                backgroundColor: isDarkMode ? "var(--bg-surface-surface-40, rgba(2, 2, 2, 0.40))" : "transparent",
                border: isDarkMode ? "1px solid rgba(255, 255, 255, 0.20)" : "1px solid rgba(0, 0, 0, 0.1)",
                backdropFilter: isDarkMode ? "blur(25px)" : "none",
                boxShadow: isDarkMode
                  ? "0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -2px rgba(0, 0, 0, 0.05)"
                  : "none",
              }}
            >
              <BalanceOfDisplay
                contractAddress={contractData.address}
                contractAbi={contractData.abi}
                refreshDisplayVariables={refreshDisplayVariables}
              />
            </div>
          </div>

          <div className="col-span-1 lg:col-span-2 flex flex-col gap-6">
            <div
              className="tab-container"
              style={{
                border: isDarkMode
                  ? "1px solid var(--stroke-sub-20, rgba(255, 255, 255, 0.20))"
                  : "1px solid rgba(0, 0, 0, 0.1)",
              }}
            >
              {tabs.map(tab => (
                <button
                  key={tab.id}
                  className={`tab-button ${activeTab === tab.id ? "active" : ""}`}
                  onClick={() => setActiveTab(tab.id)}
                >
                  <span
                    className="tab-text typography-uppercase"
                    style={{
                      color:
                        activeTab === tab.id
                          ? "black"
                          : isDarkMode
                            ? "rgba(255, 255, 255, 0.6)"
                            : "rgba(24, 24, 24, 0.6)",
                    }}
                  >
                    {tab.label}
                  </span>
                </button>
              ))}
            </div>
            <div className="z-10">
              <div
                className="rounded-[16px] flex flex-col relative bg-component"
                style={{
                  border: isDarkMode
                    ? "1px solid var(--stroke-sub-20, rgba(255, 255, 255, 0.20))"
                    : "1px solid rgba(0, 0, 0, 0.1)",
                }}
              >
                <div className="p-5 divide-y divide-secondary">
                  {activeTab === "read" && <ContractReadMethods deployedContractData={contractData as any} />}
                  {activeTab === "write" && (
                    <ContractWriteMethods
                      deployedContractData={contractData as any}
                      onChange={triggerRefreshDisplayVariables}
                    />
                  )}
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
