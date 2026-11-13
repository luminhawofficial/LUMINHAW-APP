(() => {
  const statusElement = document.getElementById("status");
  const titleElement = document.getElementById("title");
  const detailsSection = document.getElementById("payment-details");
  const detailsList = document.getElementById("details-list");
  const instructionElement = document.getElementById("instruction");
  const form = document.getElementById("decision-form");
  const confirmationField = document.getElementById("confirmation-field");
  const submitButton = document.getElementById("submit-button");
  const fragment = new URLSearchParams(window.location.hash.slice(1));
  let token = fragment.get("token") || "";
  const endpoint = fragment.get("endpoint") || "";

  window.history.replaceState(null, "", window.location.pathname);

  function setStatus(message) {
    statusElement.textContent = message;
  }

  function validEndpoint(value) {
    try {
      const url = new URL(value);
      return url.protocol === "https:" &&
        url.hostname.endsWith(".supabase.co") &&
        url.username === "" &&
        url.password === "" &&
        url.pathname === "/functions/v1/payment-email-action" &&
        url.search === "" &&
        url.hash === "";
    } catch {
      return false;
    }
  }

  async function send(payload) {
    const response = await fetch(endpoint, {
      method: "POST",
      mode: "cors",
      credentials: "omit",
      cache: "no-store",
      referrerPolicy: "no-referrer",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ ...payload, token }),
    });
    const result = await response.json();
    if (!response.ok) throw new Error("action_unavailable");
    return result;
  }

  function addDetail(label, value) {
    const term = document.createElement("dt");
    const description = document.createElement("dd");
    term.textContent = label;
    description.textContent = value == null || value === ""
      ? "Not provided"
      : String(value);
    detailsList.append(term, description);
  }

  function addConfirmation(action) {
    const label = document.createElement("label");
    const input = document.createElement(
      action === "approve" ? "input" : "textarea",
    );
    if (action === "approve") {
      input.type = "checkbox";
      input.name = "confirm_received";
      input.required = true;
      label.append(
        input,
        document.createTextNode(
          " I verified that this exact transaction was received in the official GCash account.",
        ),
      );
    } else {
      const reasonLabel = document.createElement("span");
      reasonLabel.textContent = "Reason for rejection";
      input.name = "rejection_reason";
      input.maxLength = 1000;
      input.required = true;
      label.append(reasonLabel, input);
    }
    confirmationField.replaceChildren(label);
  }

  async function load() {
    if (!token || !validEndpoint(endpoint)) {
      setStatus(
        "This payment action is invalid or unavailable. Request a new payment notification.",
      );
      return;
    }
    try {
      const payment = await send({ intent: "preview" });
      if (payment.action !== "approve" && payment.action !== "reject") {
        throw new Error("action_unavailable");
      }
      titleElement.textContent = payment.action === "approve"
        ? "Verify and approve payment"
        : "Review and reject payment";
      addDetail("Customer", payment.customer);
      addDetail("Plan", payment.plan);
      addDetail(
        "Amount",
        `${payment.currency} ${(payment.amount_centavos / 100).toFixed(2)}`,
      );
      addDetail("Reference", payment.reference);
      addDetail(
        "Entered payment date/time",
        `${payment.payment_date} ${payment.payment_time || ""}`.trim(),
      );
      instructionElement.textContent = payment.action === "approve"
        ? "Compare the entered details with the receipt, then verify the transaction in authorized GCash merchant or provider records. A receipt image alone does not prove that money was received."
        : "Confirm that this payment should be rejected. Premium will remain inactive.";
      addConfirmation(payment.action);
      detailsSection.hidden = false;
      form.hidden = false;
      setStatus(
        "Opening this page does not change payment status. The action is recorded only after you confirm.",
      );
      form.addEventListener("submit", async (event) => {
        event.preventDefault();
        if (!form.reportValidity()) return;
        submitButton.disabled = true;
        setStatus("Submitting your confirmed decision…");
        const approval = payment.action === "approve";
        const reason = form.elements.namedItem("rejection_reason");
        try {
          const result = await send({
            intent: "confirm",
            confirm_received: approval &&
              form.elements.namedItem("confirm_received").checked,
            rejection_reason: reason ? reason.value.trim() : "",
          });
          token = "";
          form.hidden = true;
          titleElement.textContent = approval
            ? "Payment approved"
            : "Payment rejected";
          setStatus(result.message || "The payment decision was recorded.");
        } catch {
          submitButton.disabled = false;
          setStatus(
            "This action could not be completed. The link may have expired or already been used. Request a refreshed payment notification before retrying.",
          );
        }
      });
    } catch {
      token = "";
      setStatus(
        "This payment action is invalid, expired, or unavailable. Request a new payment notification if needed.",
      );
    }
  }

  void load();
})();
