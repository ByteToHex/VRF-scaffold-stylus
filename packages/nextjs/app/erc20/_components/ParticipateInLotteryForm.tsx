"use client";

import { useEffect, useState } from "react";
import { Abi, Address, TransactionReceipt } from "viem";
import {
  useAccount,
  useConfig,
  useReadContract,
  useWaitForTransactionReceipt,
  useWalletClient,
  useWriteContract,
} from "wagmi";
import { useTransactor } from "~~/hooks/scaffold-eth";
import { useTargetNetwork } from "~~/hooks/scaffold-eth/useTargetNetwork";
import { AllowedChainIds } from "~~/utils/scaffold-stylus";
import { simulateContractWriteAndNotifyError, getParsedErrorWithAllAbis } from "~~/utils/scaffold-eth/contract";
import { notification } from "~~/utils/scaffold-eth";
import { TxReceipt } from "~~/app/debug/_components/contract";

type ParticipateInLotteryFormProps = {
  contractAddress: Address;
  contractAbi: Abi;
  onChange: () => void;
};

export const ParticipateInLotteryForm = ({ contractAddress, contractAbi, onChange }: ParticipateInLotteryFormProps) => {
  const { address, chain, isConnected } = useAccount();
  const { data: walletClient } = useWalletClient();
  const writeTxn = useTransactor();
  const { targetNetwork } = useTargetNetwork();

  const { data: result, isPending, writeContractAsync } = useWriteContract();
  const wagmiConfig = useConfig();

  // Get lotteryEntryFee
  const { data: lotteryEntryFee } = useReadContract({
    address: contractAddress,
    functionName: "lotteryEntryFee",
    abi: contractAbi,
    chainId: targetNetwork.id,
    query: {
      enabled: !!contractAddress,
    },
  });

  // Debug: Check each condition (after lotteryEntryFee is declared)
  const isWalletConnected = isConnected && !!address;
  const isCorrectNetwork = chain && chain.id === targetNetwork.id;
  const hasWalletClient = !!walletClient;
  const hasEntryFee = !!lotteryEntryFee;

  const writeDisabled = !isWalletConnected || !isCorrectNetwork || !hasWalletClient;

  // Create helpful tooltip message
  const getTooltipMessage = () => {
    if (!isWalletConnected) return "Please connect your wallet";
    if (!isCorrectNetwork)
      return `Wrong network. Please switch to ${targetNetwork.name} (Chain ID: ${targetNetwork.id}). Current: ${chain?.name || "Unknown"} (Chain ID: ${chain?.id || "Unknown"})`;
    if (!hasWalletClient) return "Wallet client not ready. Please wait...";
    if (!hasEntryFee) return "Loading entry fee...";
    return "";
  };

  const [displayedTxResult, setDisplayedTxResult] = useState<TransactionReceipt>();
  const { data: txResult } = useWaitForTransactionReceipt({
    hash: result,
  });

  useEffect(() => {
    setDisplayedTxResult(txResult);
  }, [txResult]);

  const handleParticipate = async () => {
    if (!isConnected || !address) {
      notification.error("Please connect your wallet");
      return;
    }

    if (!writeContractAsync || !lotteryEntryFee) {
      notification.error("Contract not ready. Please wait...");
      return;
    }

    try {
      const writeContractObj: any = {
        address: contractAddress,
        functionName: "participateInLottery",
        abi: contractAbi,
        args: [],
        value: lotteryEntryFee as bigint,
      };

      await simulateContractWriteAndNotifyError({
        wagmiConfig,
        writeContractParams: writeContractObj,
        chainId: targetNetwork.id as AllowedChainIds,
      });

      const makeWriteWithParams = () => writeContractAsync(writeContractObj);
      await writeTxn(makeWriteWithParams);
      onChange();
    } catch (e: any) {
      console.error("⚡️ ~ file: ParticipateInLotteryForm.tsx:handleParticipate ~ error", e);
      const parsedError = getParsedErrorWithAllAbis(e, targetNetwork.id as AllowedChainIds);
      notification.error(parsedError);
    }
  };

  return (
    <div className="py-5 space-y-3 first:pt-0 last:pb-1">
      <div className="flex flex-col gap-3">
        <p className="font-medium my-0 break-words function-name">participateInLottery</p>
        <div className="flex flex-col gap-2">
          {displayedTxResult && (
            <div className="w-full">
              <TxReceipt txResult={displayedTxResult} />
            </div>
          )}
          <div className="flex flex-col gap-2">
            {/* Debug info - remove in production if desired */}
            {(writeDisabled || !hasEntryFee) && (
              <div className="text-xs text-base-content/60 p-2 bg-base-200 rounded">
                <div>Status: {isWalletConnected ? "✓ Connected" : "✗ Not Connected"}</div>
                <div>
                  Network:{" "}
                  {isCorrectNetwork
                    ? `✓ ${chain?.name} (${chain?.id})`
                    : `✗ ${chain?.name || "None"} (${chain?.id || "None"}) → Need ${targetNetwork.name} (${targetNetwork.id})`}
                </div>
                <div>Wallet Client: {hasWalletClient ? "✓ Ready" : "✗ Not Ready"}</div>
                <div>Entry Fee: {hasEntryFee ? "✓ Loaded" : "✗ Loading..."}</div>
              </div>
            )}
            <div className="flex justify-end">
              <div
                className={`flex ${
                  (writeDisabled || !hasEntryFee) &&
                  "tooltip tooltip-bottom tooltip-secondary before:content-[attr(data-tip)] before:-translate-x-1/3 before:left-auto before:transform-none"
                }`}
                data-tip={getTooltipMessage() || undefined}
              >
                <button
                  className="send-button"
                  disabled={writeDisabled || isPending || !lotteryEntryFee}
                  onClick={handleParticipate}
                >
                  {isPending && <span className="loading loading-spinner loading-xs"></span>}
                  Participate
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
