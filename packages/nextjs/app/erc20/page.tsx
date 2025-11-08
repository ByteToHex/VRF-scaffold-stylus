import { ERC20Interactions } from "./_components/ERC20Interactions";
import type { NextPage } from "next";
import { getMetadata } from "~~/utils/scaffold-eth/getMetadata";

export const metadata = getMetadata({
  title: "ERC20 Token",
  description: "Interact with ERC20 token contract",
});

const ERC20Page: NextPage = () => {
  return <ERC20Interactions />;
};

export default ERC20Page;
