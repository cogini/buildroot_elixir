################################################################################
#
# otp-app
#
################################################################################

# ELIXIR_APP_VERSION = 0.1
# ELIXIR_APP_SITE = $(ELIXIR_APP_PKGDIR).
# ELIXIR_APP_SITE_METHOD = local
ELIXIR_APP_VERSION = 0.1
ELIXIR_APP_SITE = $(call github,cogini,mix-deploy-example,$(ELIXIR_APP_VERSION))
ELIXIR_APP_LICENSE = Apache-2.0
DEPENDENCIES = erlang

define ELIXIR_APP_BUILD_CMDS
	env
endef

define ELIXIR_APP_INSTALL_TARGET_CMDS
	$(INSTALL) -d -m 0755 $(TARGET_DIR)/srv/app
	# $(INSTALL) -D -m 0755 $(@D)/hello $(TARGET_DIR)/usr/bin
endef

define ELIXIR_APP_INSTALL_INIT_SYSTEMD
    $(INSTALL) -D -m 644 $(ELIXIR_APP_PKGDIR)/otp-app.service \
        $(TARGET_DIR)/usr/lib/systemd/system/otp-app.service
    mkdir -p $(TARGET_DIR)/etc/systemd/system/multi-user.target.wants
    ln -fs ../../../../usr/lib/systemd/system/erlang-app.service \
        $(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/erlang-app.service
endef

# define ELIXIR_APP_USERS
#     nonroot -1 nonroot -1 * - - - app user
# endef

# define ELIXIR_APP_PERMISSIONS
#     /srv/app  d  750  nonroot  nonroot   -  -  -  -  -
# endef

$(eval $(generic-package))
