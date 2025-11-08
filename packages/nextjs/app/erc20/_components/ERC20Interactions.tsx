"use client";

import { useMemo, useReducer } from "react";
import { useTheme } from "next-themes";
import { Address } from "~~/components/scaffold-eth";
import { useTargetNetwork } from "~~/hooks/scaffold-eth/useTargetNetwork";
import { BalanceOfDisplay } from "./BalanceOfDisplay";
import { LotteryEntryFeeDisplay } from "./LotteryEntryFeeDisplay";
import { ParticipateInLotteryForm } from "./ParticipateInLotteryForm";
import requiredContracts from "~~/contracts/requiredContracts ";

const ERC20_CONTRACT_NAME = "erc20-example";
const VRF_CONTRACT_NAME = "vrf-consumer";

export const ERC20Interactions = () => {
  const [refreshDisplayVariables, triggerRefreshDisplayVariables] = useReducer(value => !value, false);
  const { targetNetwork } = useTargetNetwork();
  const { resolvedTheme } = useTheme();
  const isDarkMode = useMemo(() => resolvedTheme === "dark", [resolvedTheme]);

  // Get contract data from requiredContracts.ts
  const erc20ContractData = useMemo(() => {
    const chainId = targetNetwork.id.toString();
    const contracts = requiredContracts as any;
    return contracts[chainId]?.[ERC20_CONTRACT_NAME];
  }, [targetNetwork.id]);

  const vrfContractData = useMemo(() => {
    const chainId = targetNetwork.id.toString();
    const contracts = requiredContracts as any;
    return contracts[chainId]?.[VRF_CONTRACT_NAME];
  }, [targetNetwork.id]);

  if (!erc20ContractData) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <p className="text-3xl">
          {`Contract "${ERC20_CONTRACT_NAME}" not found for chain "${targetNetwork.name}" (${targetNetwork.id})!`}
        </p>
      </div>
    );
  }

  if (!vrfContractData) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <p className="text-3xl">
          {`Contract "${VRF_CONTRACT_NAME}" not found for chain "${targetNetwork.name}" (${targetNetwork.id})!`}
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
                {/* Title */}
                <div
                  style={{
                    color: isDarkMode ? "#30B4ED" : "#30B4ED",
                    fontSize: "2rem",
                    fontWeight: "800",
                    lineHeight: "1.2",
                  }}
                >
                  Lottery Token (LUK)
                </div>

                {/* VRF Contract Address */}
                <div className="flex flex-col gap-1">
                  <span
                    style={{
                      color: isDarkMode ? "rgba(255, 255, 255, 0.7)" : "rgba(0, 0, 0, 0.7)",
                      fontSize: "0.875rem",
                      fontWeight: "500",
                    }}
                  >
                    VRF Contract:
                  </span>
                  <Address address={vrfContractData.address} onlyEnsOrAddress />
                </div>

                {/* ERC20 Contract Address */}
                <div className="flex flex-col gap-1">
                  <span
                    style={{
                      color: isDarkMode ? "rgba(255, 255, 255, 0.7)" : "rgba(0, 0, 0, 0.7)",
                      fontSize: "0.875rem",
                      fontWeight: "500",
                    }}
                  >
                    ERC20 Contract:
                  </span>
                  <Address address={erc20ContractData.address} onlyEnsOrAddress />
                </div>
              </div>
            </div>

            {/* Lottery Entry Fee Display */}
            <div
              className="rounded-xl px-6 lg:px-8 py-4 mb-4"
              style={{
                backgroundColor: isDarkMode ? "var(--bg-surface-surface-40, rgba(2, 2, 2, 0.40))" : "transparent",
                border: isDarkMode ? "1px solid rgba(255, 255, 255, 0.20)" : "1px solid rgba(0, 0, 0, 0.1)",
                backdropFilter: isDarkMode ? "blur(25px)" : "none",
                boxShadow: isDarkMode
                  ? "0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -2px rgba(0, 0, 0, 0.05)"
                  : "none",
              }}
            >
              <LotteryEntryFeeDisplay
                contractAddress={vrfContractData.address}
                contractAbi={vrfContractData.abi}
                refreshDisplayVariables={refreshDisplayVariables}
              />
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
                contractAddress={erc20ContractData.address}
                contractAbi={erc20ContractData.abi}
                refreshDisplayVariables={refreshDisplayVariables}
              />
            </div>
          </div>

          <div className="col-span-1 lg:col-span-2 flex flex-col gap-6">
            <div className="z-10">
              <div
                className="rounded-[16px] flex flex-col relative bg-component"
                style={{
                  border: isDarkMode
                    ? "1px solid var(--stroke-sub-20, rgba(255, 255, 255, 0.20))"
                    : "1px solid rgba(0, 0, 0, 0.1)",
                  minHeight: "400px",
                }}
              >
                <div className="p-8">
                  <ParticipateInLotteryForm
                    contractAddress={vrfContractData.address}
                    contractAbi={vrfContractData.abi}
                    onChange={triggerRefreshDisplayVariables}
                  />
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
