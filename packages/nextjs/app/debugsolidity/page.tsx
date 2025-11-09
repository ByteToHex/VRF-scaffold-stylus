import { DebugContractsSolidity } from "./_components/DebugContractsSolidity";
import type { NextPage } from "next";
import { getMetadata } from "~~/utils/scaffold-eth/getMetadata";

export const metadata = getMetadata({
  title: "Debug Solidity Contracts",
  description: "Debug your deployed Solidity contracts in an easy way",
});

const DebugSolidity: NextPage = () => {
  return <DebugContractsSolidity />;
};

export default DebugSolidity;
