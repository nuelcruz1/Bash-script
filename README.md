You can test if your `deploy.sh` script is executable in your terminal using a couple of simple commands.

The most direct way is to try running it, but the reliable way is to check its permissions.

-----

## 1\. Check Permissions with `ls -l`

The `ls -l` command lists file details, including permissions. Look for the 'x' (execute) flag.

```bash
ls -l deploy.sh
```

### ✅ Interpretation

The output will look something like this:

| Permissions Check | Status | Meaning |
| :--- | :--- | :--- |
| **`-rwxr-xr-x`** | **Executable** | The first three characters (`rwx`) include the **'x'**. You're good to go. |
| **`-rw-r--r--`** | **NOT Executable** | The first three characters (`rw-`) are missing the **'x'**. You need to run `chmod +x deploy.sh`. |

-----

## 2\. Test Execution

The quickest test is to try running the script using the relative path, which requires the execute bit to be set.

```bash
./deploy.sh
```

### ✅ Interpretation

  * **If it's executable:** The script will run and immediately start asking for your input parameters (e.g., "Enter Git Repository URL...").
  * **If it's NOT executable:** The terminal will return an error like:
    ```bash
    bash: ./deploy.sh: Permission denied
    ```
    If you see this error, run `chmod +x deploy.sh` and try again.
