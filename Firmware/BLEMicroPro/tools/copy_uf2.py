Import("env")

def build_uf2(source, target, env):
    import os
    import subprocess
    import sys
    framework = env.PioPlatform().get_package_dir("framework-arduinoadafruitnrf52")
    converter = os.path.join(framework, "tools", "uf2conv", "uf2conv.py")
    output = os.path.join(env.subst("$PROJECT_DIR"), "VibeWatch-BLE-Micro-Pro.uf2")
    input_hex = os.path.join(
        env.subst("$PROJECT_BUILD_DIR"), env.subst("$PIOENV"),
        env.subst("$PROGNAME") + ".hex",
    )
    subprocess.check_call([
        sys.executable, converter, "-f", "0xADA52840", "-c", "-o", output,
        input_hex,
    ])
    print("Firmware ready: " + output)

env.AddPostAction("$BUILD_DIR/${PROGNAME}.hex", build_uf2)
