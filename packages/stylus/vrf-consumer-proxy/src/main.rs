// The Stylus entrypoint for the proxy contract
#[cfg(all(not(test), not(feature = "export-abi")))]
#[no_mangle]
pub extern "C" fn entrypoint() -> u8 {
    stylus_sdk::entrypoint::<vrf_consumer_proxy::VrfConsumerProxy>()
}

