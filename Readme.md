# Sunshine Script Installer Template

This repository is designed to be used as a template for creating similar projects. It allows you to maintain an up-to-date version of the template while also customizing and adding your own content.

## Using This Repository as a Template

To use this repository as a template for your own project, follow these steps:

1. **Create a New Repository from the Template**
   - Navigate to the main page of this repository.
   - Above the file list, click the **Use this template** button.
   - Follow the prompts to create a new repository from this template.

## Setting Up the Upstream Repository

Once you have created your project from this template, you should set up this repository as an upstream to easily pull the latest changes:

1. **Add the Upstream Repository**
   - Open your terminal.
   - Change the current working directory to your local project.
   - Run the following command to add this repository as an upstream:
     ```
     git remote add upstream https://github.com/Nonary/SunshineScriptInstaller.git
     ```

2. **Verify the Upstream Repository**
   - To ensure the upstream repository was added correctly, you can run:
     ```
     git remote -v
     ```
   - You should see the URL for your fork as `origin`, and the URL for the original repository as `upstream`.

## Syncing with the Upstream Repository

To keep your repository up-to-date with the changes made in the template, you can merge changes from the upstream repository into your project:

1. **Fetch the Latest Changes from Upstream**
   - Run the following command to fetch the branches and their respective commits from the upstream repository:
     ```
     git fetch upstream
     ```

2. **Merge the Changes from Upstream/Main into Your Branch**
   - Ensure you are on your main branch by running:
     ```
     git checkout main
     ```
   - Merge the changes from the upstream main branch:
     ```
     git merge upstream/main --squash --no-commit --allow-unrelated-histories
     ```
   - If there are no conflicts, this will update your branch with the latest changes.

3. **Push the Merged Changes**
   - After merging, push the changes to your GitHub repository:
     ```
     git push origin main
     ```


### Customizing the Script

### Steps to Customize
1. Add your custom functions to the `Events.ps1` file.
2. Implement your desired actions in the `OnStreamStart` and `OnStreamEnd` functions.
3. Update the `-n` parameter in `Install.bat` and `Uninstall.bat` to match the name of your script.

### Understanding Event Handlers

The `Events.ps1` file includes predefined PowerShell functions that act as event handlers for specific streaming events in the Sunshine application. You can tailor your streaming setup by adding your own code to these functions:

- **OnStreamStart**: This function is activated when your stream starts. You can add initialization code here, such as setting up your environment, logging the start time, or enabling certain features in your stream setup.

- **OnStreamEnd**: This function is invoked when your stream ends. It's an ideal location for cleanup code, like deallocating resources, logging the end of the session, or sending post-stream notifications.

> **Note**: Don't forget to update the script name in both `Install.bat` and `Uninstall.bat`. If not updated, it will default to `SunshineScriptInstaller`.

### Regularly Updating Your Repository

To ensure that your project remains up-to-date with the latest features and bug fixes, it's recommended to regularly sync with the upstream repository. This involves pulling the latest changes from the original source and merging them into your local repository. Staying updated can help you avoid conflicts and benefit from the latest improvements made by other contributors.

### Engaging with the Community

If you find the Sunshine project beneficial, consider starring the repository on GitHub. This not only shows appreciation to the maintainers but also helps increase the visibility of the project, attracting more contributors and users.

- **Star the Repository**: Visit the main page of the Sunshine GitHub repository and click on the 'Star' button to bookmark it. This is a simple way to acknowledge the work of the developers and maintainers.

- **Follow Maintenance Updates**: Keep an eye on the repository for ongoing updates and changes. Regular visits can keep you informed about new features and important fixes.

- **Contribute to the Template**: If you have ideas on how to improve the project or if you've developed enhancements that could benefit others, consider contributing your changes back to the repository. 