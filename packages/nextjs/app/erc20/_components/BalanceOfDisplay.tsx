"use client";

import { useEffect, useMemo, useState } from "react";
import { useTheme } from "next-themes";
import { Abi, Address } from "viem";
import { useReadContract } from "wagmi";
import { useAccount } from "wagmi";
import { ArrowPathIcon } from "@heroicons/react/24/outline";
import { formatUnits } from "viem";
import { useTargetNetwork } from "~~/hooks/scaffold-eth/useTargetNetwork";
import { getParsedError, notification } from "~~/utils/scaffold-eth";

type BalanceOfDisplayProps = {
  contractAddress: Address;
  contractAbi: Abi;
  refreshDisplayVariables: boolean;
};

export const BalanceOfDisplay = ({ contractAddress, contractAbi, refreshDisplayVariables }: BalanceOfDisplayProps) => {
  const { targetNetwork } = useTargetNetwork();
  const { resolvedTheme } = useTheme();
  const { address: connectedAddress } = useAccount();
  const isDarkMode = useMemo(() => resolvedTheme === "dark", [resolvedTheme]);
  const [decimals, setDecimals] = useState<number>(18); // Default to 18

  // First, get the decimals from the contract
  const { data: decimalsData, refetch: refetchDecimals } = useReadContract({
    address: contractAddress,
    functionName: "decimals",
    abi: contractAbi,
    chainId: targetNetwork.id,
    query: {
      enabled: !!contractAddress,
      retry: false,
    },
  });

  // Update decimals when fetched
  useEffect(() => {
    if (decimalsData !== undefined) {
      setDecimals(Number(decimalsData));
    }
  }, [decimalsData]);

  // Get balanceOf for the connected address
  const {
    data: balanceResult,
    isFetching,
    refetch,
    error,
  } = useReadContract({
    address: contractAddress,
    functionName: "balanceOf",
    abi: contractAbi,
    args: connectedAddress ? [connectedAddress] : undefined,
    chainId: targetNetwork.id,
    query: {
      enabled: !!connectedAddress && !!contractAddress,
      retry: false,
    },
  });

  // Animation config - simplified for this component
  const showAnimation = false;

  useEffect(() => {
    refetch();
    refetchDecimals();
  }, [refetch, refetchDecimals, refreshDisplayVariables]);

  useEffect(() => {
    if (error) {
      const parsedError = getParsedError(error);
      notification.error(parsedError);
    }
  }, [error]);

  const formatBalance = (balance: bigint | undefined): string => {
    if (balance === undefined || balance === null) {
      return "--";
    }
    try {
      return formatUnits(balance, decimals);
    } catch {
      return balance.toString();
    }
  };

  return (
    <div className="space-y-1 pb-2">
      <div className="flex items-center">
        <h3
          className="mb-0 break-all"
          style={{
            color: isDarkMode ? "#30B4ED" : "#30B4ED",
            fontSize: "1.5rem",
            fontWeight: "800",
            lineHeight: "1.2",
          }}
        >
          balanceOf
        </h3>
        <button className="btn btn-ghost btn-xs" onClick={async () => await refetch()}>
          {isFetching ? (
            <span className="loading loading-spinner loading-xs"></span>
          ) : (
            <ArrowPathIcon className="h-3 w-3 cursor-pointer" aria-hidden="true" />
          )}
        </button>
      </div>
      <div className="font-medium flex flex-col items-start">
        <div>
          {!connectedAddress ? (
            <div
              className="break-all block transition bg-transparent"
              style={{
                color: isDarkMode ? "rgba(255, 255, 255, 0.6)" : "rgba(0, 0, 0, 0.6)",
              }}
            >
              -- (No address connected)
            </div>
          ) : (
            <div
              className={`break-all block transition bg-transparent ${
                showAnimation ? "bg-warning rounded-sm animate-pulse-fast" : ""
              }`}
              style={{
                color: isDarkMode ? "white" : "black",
              }}
            >
              {isFetching ? (
                <span className="loading loading-spinner loading-xs"></span>
              ) : (
                formatBalance(balanceResult as bigint | undefined)
              )}
            </div>
          )}
        </div>
        {connectedAddress && (
          <div
            className="text-xs mt-1"
            style={{
              color: isDarkMode ? "rgba(255, 255, 255, 0.5)" : "rgba(0, 0, 0, 0.5)",
            }}
          >
            Address: <span className="font-mono">{connectedAddress}</span>
          </div>
        )}
      </div>
    </div>
  );
};
