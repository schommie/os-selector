#![no_main]
#![no_std]

use uefi::prelude::*;
use uefi::runtime::{
    self, ResetType, VariableAttributes, VariableVendor,
};

#[entry]
fn main() -> Status {
    uefi::helpers::init().unwrap();

    const WINDOWS_BOOT_ENTRY: u16 = 0x0001;

    let attributes = VariableAttributes::NON_VOLATILE
        | VariableAttributes::BOOTSERVICE_ACCESS
        | VariableAttributes::RUNTIME_ACCESS;
    let data = WINDOWS_BOOT_ENTRY.to_le_bytes();

    match runtime::set_variable(
        uefi::cstr16!("BootNext"),
        &VariableVendor::GLOBAL_VARIABLE,
        attributes,
        &data,
    ) {
        Ok(()) => {
            uefi::println!("BootNext set to Windows (0001)");
            uefi::println!("Rebooting...");

            runtime::reset(
                ResetType::COLD,
                Status::SUCCESS,
                None,
            );
        }
        Err(err) => {
            uefi::println!("Failed to set BootNext: {:?}", err);
            Status::ABORTED
        }
    }
}