
# Workflow for Reporting and Fixing Bugs

## 1. Fork the Repository
- Go to the repository and click the "Fork" button at the top right of the page. This creates a copy of the repository under your GitHub account.

## 2. Clone the Forked Repository
- Clone your forked repository to your local machine using the following command:
  ```bash
  git clone https://github.com/<your-username>/repo-name.git
  ```

## 3. Create a New Branch
- Before making changes, create a new branch for your bug fix:
  ```bash
  git checkout -b bug-fix-<description>
  ```

## 4. Create an Issue for the Bug
- If you identify a bug, create an issue in the repository describing the bug. Include the following details:
  - **Bug Description**: What is the bug?
  - **Steps to Reproduce**: What actions lead to the bug?
  - **Expected Behavior**: What should happen?
  - **Actual Behavior**: What happens instead?

## 5. Fix the Bug
- After creating the issue, fix the bug in your local branch. Make sure to:
  - Test your fix locally.
  - Add a test case to the `assembler/examples` folder that demonstrates the issue and ensures the fix works.

## 6. Commit the Changes
- Once you’ve fixed the bug and added the test case, commit your changes with a clear commit message:
  ```bash
  git add .
  git commit -m "Fix bug: <describe the bug fix> and add test case"
  ```

## 7. Push Changes to GitHub
- Push your changes to your forked repository:
  ```bash
  git push origin bug-fix-<description>
  ```

## 8. Create a Pull Request
- Go to your repository on GitHub, and click on the "Compare & pull request" button. This will let you open a pull request (PR) for the repository you forked from.
- In the PR description, reference the issue number and clearly explain what bug you fixed, how you fixed it, and which test case you added to verify the fix.


### Reporting Bugs:
- Always create an issue for every bug you encounter. The issue should include:
  - **Bug Description**
  - **Steps to Reproduce**
  - **Expected vs Actual Behavior**
  - **Screenshots or logs (if applicable)**
