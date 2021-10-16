#
# Copyright (C) 2020-2021 Eugene Hutorny <eugene@hutorny.in.ua>
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=MODBUS Data Aquisition Service
LUCI_DEPENDS:=+kmod-usb-serial +kmod-usb-serial-ftdi +libmodbus +lua-libmodbus +luasocket +luabitop +lua-cjson +luci-mod-rpc

PKG_MAINTAINER:=Eugene Hutorny <eugene@hutorny.in.ua>

PKG_LICENSE:=GPLv2

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
