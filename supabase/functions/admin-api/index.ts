import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";
import { authenticatedUserId, enforceRateLimit } from "../_shared/auth.ts";
import { isValidAnnouncementSchedule } from "../_shared/announcements.ts";
import { deliverPaymentNotification } from "../_shared/payment-email.ts";
import { corsHeaders, jsonResponse, readJsonBody } from "../_shared/http.ts";
import { parseAdminPlantCatalogInput } from "./plant-catalog-input.ts";

type AdminRole = "admin" | "moderator";

type AdminContext = {
  userId: string;
  role: AdminRole;
  client: SupabaseClient;
};

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function serviceClient(): SupabaseClient | null {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceRoleKey) {
    console.error("Admin API service credentials are not configured.");
    return null;
  }
  return createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

function hasRole(
  role: AdminRole,
  allowed: readonly AdminRole[],
): boolean {
  return allowed.includes(role);
}

async function adminContext(request: Request): Promise<
  AdminContext | Response
> {
  const userId = await authenticatedUserId(request);
  if (userId instanceof Response) return userId;

  const rateLimitResponse = await enforceRateLimit(
    userId,
    "admin-dashboard",
    180,
    3600,
  );
  if (rateLimitResponse) return rateLimitResponse;

  const client = serviceClient();
  if (!client) {
    return jsonResponse({ error: { code: "admin_service_unavailable" } }, 503);
  }

  const { data: assignment, error } = await client
    .from("admin_roles")
    .select("role, status")
    .eq("user_id", userId)
    .maybeSingle();
  if (error) {
    console.error("Admin role lookup failed:", error.code);
    return jsonResponse(
      { error: { code: "admin_authorization_unavailable" } },
      503,
    );
  }
  if (
    !assignment || assignment.status !== "active" ||
    !["admin", "moderator"].includes(assignment.role)
  ) {
    return jsonResponse(
      { error: { code: "administrator_access_required" } },
      403,
    );
  }

  return {
    userId,
    role: assignment.role as AdminRole,
    client,
  };
}

async function writeAudit(
  context: AdminContext,
  action: string,
  resourceType: string,
  resourceId: string | null,
  metadata: Record<string, unknown> = {},
): Promise<boolean> {
  const { error } = await context.client.rpc("admin_write_audit_log", {
    p_actor_id: context.userId,
    p_action: action,
    p_resource_type: resourceType,
    p_resource_id: resourceId,
    p_metadata: metadata,
  });
  if (error) {
    console.error("Admin audit write failed:", error.code);
    return false;
  }
  return true;
}

async function savePlantCatalogRecord(
  context: AdminContext,
  body: Record<string, unknown>,
  isUpdate: boolean,
): Promise<Response> {
  if (!hasRole(context.role, ["admin"])) {
    return jsonResponse({ error: { code: "insufficient_role" } }, 403);
  }

  const parsed = parseAdminPlantCatalogInput(body, isUpdate);
  if (!parsed.ok) {
    return jsonResponse({ error: { code: parsed.code } }, 400);
  }
  const input = parsed.value;
  const { data: plantId, error } = await context.client.rpc(
    "admin_save_plant_catalog",
    {
      p_actor_id: context.userId,
      p_plant_id: input.id,
      p_catalog: input.catalog,
      p_care: input.care,
      p_field_references: input.fieldReferences,
      p_image_url: input.imageUrl,
      p_image_source_url: input.imageSourceUrl,
      p_date_updated: input.dateUpdated,
    },
  );
  if (error || typeof plantId !== "string") {
    console.error(
      "Admin plant catalog save failed:",
      error?.code ?? "missing_plant_id",
    );
    if (error?.code === "P0002") {
      return jsonResponse(
        { error: { code: "plant_catalog_record_not_found" } },
        404,
      );
    }
    return jsonResponse(
      { error: { code: "plant_catalog_save_failed" } },
      503,
    );
  }

  if (
    !await writeAudit(
      context,
      isUpdate ? "plant_catalog.updated" : "plant_catalog.created",
      "plant_catalog",
      plantId,
      { fields: Object.keys(input.fieldReferences) },
    )
  ) {
    return jsonResponse(
      { error: { code: "plant_catalog_audit_unavailable" } },
      503,
    );
  }

  return jsonResponse({ plant_id: plantId }, isUpdate ? 200 : 201);
}

async function listPayments(
  context: AdminContext,
  body: Record<string, unknown>,
): Promise<Response> {
  if (!hasRole(context.role, ["admin"])) {
    return jsonResponse({ error: { code: "insufficient_role" } }, 403);
  }

  const status = typeof body.status === "string" ? body.status : "all";
  const rawReference = typeof body.reference === "string"
    ? body.reference.trim()
    : "";
  const reference = rawReference.replaceAll(" ", "");
  const offset = Number.isInteger(body.offset) ? Number(body.offset) : 0;
  const limit = Number.isInteger(body.limit) ? Number(body.limit) : 50;
  if (
    !["all", "pending", "approved", "rejected"].includes(status) ||
    (rawReference !== "" &&
      (!/^[0-9 ]+$/.test(rawReference) ||
        !/^\d{1,13}$/.test(reference))) ||
    offset < 0 ||
    offset > 100_000 ||
    limit < 1 ||
    limit > 100
  ) {
    return jsonResponse({ error: { code: "invalid_payment_query" } }, 400);
  }

  let paymentQuery = context.client
    .from("premium_payment_requests")
    .select(
      "id, user_id, payment_method, amount_centavos, currency, merchant_transaction_reference, payment_date, payment_time, proof_storage_path, payment_status, review_notes, rejection_reason, customer_full_name, customer_mobile_number, customer_email, reviewed_by, reviewed_by_email, reviewed_at, entitlement_expires_at, created_at, payment_plans(code, name, duration_days)",
    );
  if (status === "pending") {
    paymentQuery = paymentQuery.in("payment_status", [
      "pending",
      "under_review",
    ]);
  } else if (status === "approved" || status === "rejected") {
    paymentQuery = paymentQuery.eq("payment_status", status);
  }
  if (reference) {
    paymentQuery = paymentQuery.ilike(
      "merchant_transaction_reference",
      `%${reference}%`,
    );
  }
  const { data: payments, error } = await paymentQuery
    .order("created_at", { ascending: false })
    .range(offset, offset + limit - 1);
  if (error) {
    console.error("Admin payment query failed:", error.code);
    return jsonResponse(
      { error: { code: "payment_records_unavailable" } },
      503,
    );
  }

  const userIds = [
    ...new Set((payments ?? []).map((payment) => payment.user_id)),
  ];
  const profileResult = userIds.length === 0
    ? { data: [], error: null }
    : await context.client
      .from("profiles")
      .select("id, display_name")
      .in("id", userIds);
  if (profileResult.error) {
    console.error("Payment profile lookup failed:", profileResult.error.code);
    return jsonResponse(
      { error: { code: "payment_user_details_unavailable" } },
      503,
    );
  }
  const profiles = new Map(
    (profileResult.data ?? []).map((profile) => [profile.id, profile]),
  );

  const rows = await Promise.all((payments ?? []).map(async (payment) => {
    let receiptUrl: string | null = null;
    if (payment.proof_storage_path) {
      const { data, error: signedUrlError } = await context.client.storage
        .from("premium-payment-proofs")
        .createSignedUrl(payment.proof_storage_path, 120);
      if (signedUrlError || !data?.signedUrl) {
        console.error(
          "Private payment receipt signing failed:",
          signedUrlError?.name ?? "signed_url_missing",
        );
        return null;
      }
      receiptUrl = data.signedUrl;
    }

    return {
      ...payment,
      profile: profiles.get(payment.user_id) ?? null,
      receipt_url: receiptUrl,
    };
  }));
  if (rows.some((row) => row === null)) {
    return jsonResponse(
      { error: { code: "private_receipt_unavailable" } },
      503,
    );
  }

  return jsonResponse({
    payments: rows,
    hasMore: (payments ?? []).length === limit,
    nextOffset: offset + (payments ?? []).length,
  });
}

async function listPlantRecords(
  context: AdminContext,
  table: "plant_identifications" | "plant_health_assessments",
): Promise<Response> {
  if (!hasRole(context.role, ["admin", "moderator"])) {
    return jsonResponse({ error: { code: "insufficient_role" } }, 403);
  }

  const { data: records, error } = await context.client
    .from(table)
    .select(
      "id, owner_id, plant_id, image_path, status, provider, result, created_at, completed_at",
    )
    .order("created_at", { ascending: false })
    .limit(100);
  if (error) {
    console.error(`Admin ${table} query failed:`, error.code);
    return jsonResponse({ error: { code: "plant_records_unavailable" } }, 503);
  }

  const ownerIds = [
    ...new Set((records ?? []).map((record) => record.owner_id)),
  ];
  const profileResult = ownerIds.length === 0
    ? { data: [], error: null }
    : await context.client
      .from("profiles")
      .select("id, display_name")
      .in("id", ownerIds);
  if (profileResult.error) {
    console.error(
      "Plant record profile lookup failed:",
      profileResult.error.code,
    );
    return jsonResponse(
      { error: { code: "plant_record_users_unavailable" } },
      503,
    );
  }
  const profiles = new Map(
    (profileResult.data ?? []).map((profile) => [profile.id, profile]),
  );

  const rows = await Promise.all((records ?? []).map(async (record) => {
    let imageUrl: string | null = null;
    if (record.image_path) {
      const { data, error: signedUrlError } = await context.client.storage
        .from("plant-photos")
        .createSignedUrl(record.image_path, 120);
      if (signedUrlError || !data?.signedUrl) {
        console.error(
          "Private plant image signing failed:",
          signedUrlError?.name ?? "signed_url_missing",
        );
        return null;
      }
      imageUrl = data.signedUrl;
    }
    return {
      ...record,
      profile: profiles.get(record.owner_id) ?? null,
      image_url: imageUrl,
    };
  }));
  if (rows.some((row) => row === null)) {
    return jsonResponse(
      { error: { code: "private_plant_image_unavailable" } },
      503,
    );
  }

  return jsonResponse({ records: rows });
}

async function handleAdminRequest(
  request: Request,
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: { code: "method_not_allowed" } }, 405);
  }

  const authenticated = await adminContext(request);
  if (authenticated instanceof Response) return authenticated;

  const parsed = await readJsonBody(request, 131072);
  if ("response" in parsed) return parsed.response;
  const body = parsed.body;
  if (typeof body.action !== "string") {
    return jsonResponse({ error: { code: "action_required" } }, 400);
  }

  const context = authenticated;
  switch (body.action) {
    case "session":
      return jsonResponse({
        user_id: context.userId,
        role: context.role,
        capabilities: {
          manage_roles: context.role === "admin",
          manage_payments: context.role === "admin",
          manage_plant_catalog: context.role === "admin",
          manage_users: context.role !== "moderator",
        },
      });

    case "dashboard": {
      const { data, error } = await context.client.rpc(
        "admin_dashboard_summary",
        { p_actor_id: context.userId },
      );
      if (error) {
        console.error("Admin dashboard summary failed:", error.code);
        return jsonResponse(
          { error: { code: "dashboard_data_unavailable" } },
          503,
        );
      }
      return jsonResponse({ summary: data });
    }

    case "users.list": {
      if (!hasRole(context.role, ["admin"])) {
        return jsonResponse({ error: { code: "insufficient_role" } }, 403);
      }
      const search = typeof body.search === "string"
        ? body.search.trim()
        : null;
      const limit = Number.isInteger(body.limit) ? Number(body.limit) : 25;
      const offset = Number.isInteger(body.offset) ? Number(body.offset) : 0;
      const { data, error } = await context.client.rpc("admin_list_users", {
        p_actor_id: context.userId,
        p_search: search || null,
        p_limit: limit,
        p_offset: offset,
      });
      if (error) {
        console.error("Admin user query failed:", error.code);
        return jsonResponse(
          { error: { code: "user_records_unavailable" } },
          503,
        );
      }
      return jsonResponse({ result: data });
    }

    case "users.status": {
      if (!hasRole(context.role, ["admin"])) {
        return jsonResponse({ error: { code: "insufficient_role" } }, 403);
      }
      const userId = body.user_id;
      const status = body.status;
      if (
        typeof userId !== "string" || !uuidPattern.test(userId) ||
        (status !== "active" && status !== "suspended") ||
        (status === "suspended" && userId === context.userId)
      ) {
        return jsonResponse(
          { error: { code: "invalid_user_status_request" } },
          400,
        );
      }

      const { data: targetRole, error: roleError } = await context.client
        .from("admin_roles")
        .select("role, status")
        .eq("user_id", userId)
        .maybeSingle();
      if (roleError) {
        console.error("Target administrator lookup failed:", roleError.code);
        return jsonResponse({
          error: { code: "administrator_lookup_unavailable" },
        }, 503);
      }
      if (targetRole) {
        return jsonResponse({
          error: { code: "administrator_management_required" },
        }, 403);
      }

      const auditAction = status === "suspended"
        ? "user.suspension_requested"
        : "user.reactivation_requested";
      if (
        !await writeAudit(
          context,
          auditAction,
          "user",
          userId,
          { status },
        )
      ) {
        return jsonResponse({ error: { code: "audit_log_unavailable" } }, 503);
      }

      const { data, error } = await context.client.auth.admin.updateUserById(
        userId,
        { ban_duration: status === "suspended" ? "876000h" : "none" },
      );
      if (error || !data.user) {
        console.error(
          "User status update failed:",
          error?.code ?? "user_missing",
        );
        const loggedFailure = await writeAudit(
          context,
          "user.status_change_failed",
          "user",
          userId,
          { status, error_code: error?.code ?? "user_missing" },
        );
        return jsonResponse({
          error: {
            code: loggedFailure
              ? "user_status_update_failed"
              : "user_status_and_audit_failed",
          },
        }, 503);
      }

      if (
        !await writeAudit(
          context,
          status === "suspended" ? "user.suspended" : "user.reactivated",
          "user",
          userId,
          { status },
        )
      ) {
        return jsonResponse({
          error: { code: "user_status_changed_audit_unavailable" },
        }, 503);
      }

      return jsonResponse({
        user_id: userId,
        status,
        data_preserved: true,
      });
    }

    case "roles.list": {
      if (!hasRole(context.role, ["admin"])) {
        return jsonResponse({ error: { code: "insufficient_role" } }, 403);
      }
      const { data, error } = await context.client
        .from("admin_roles")
        .select("user_id, role, status, assigned_by, created_at, updated_at")
        .order("created_at", { ascending: true })
        .limit(200);
      if (error) {
        console.error("Admin role listing failed:", error.code);
        return jsonResponse(
          { error: { code: "admin_roles_unavailable" } },
          503,
        );
      }
      const administrators = await Promise.all((data ?? []).map(async (row) => {
        const { data: userData, error: userError } = await context.client.auth
          .admin
          .getUserById(row.user_id);
        if (userError || !userData.user) {
          console.error(
            "Admin account lookup failed:",
            userError?.code ?? "user_missing",
          );
          return null;
        }
        return {
          ...row,
          email: userData.user.email ?? null,
          display_name: userData.user.user_metadata?.full_name ?? "",
        };
      }));
      if (administrators.some((row) => row === null)) {
        return jsonResponse({
          error: { code: "admin_account_details_unavailable" },
        }, 503);
      }
      return jsonResponse({ administrators });
    }

    case "roles.set": {
      if (!hasRole(context.role, ["admin"])) {
        return jsonResponse({ error: { code: "insufficient_role" } }, 403);
      }
      const targetUserId = body.user_id;
      if (
        typeof targetUserId !== "string" || !uuidPattern.test(targetUserId) ||
        typeof body.role !== "string" ||
        !["admin", "moderator"].includes(body.role) ||
        typeof body.status !== "string" ||
        !["active", "suspended"].includes(body.status)
      ) {
        return jsonResponse(
          { error: { code: "invalid_role_assignment" } },
          400,
        );
      }
      const { data, error } = await context.client.rpc("admin_set_role", {
        p_actor_id: context.userId,
        p_target_user_id: targetUserId,
        p_role: body.role,
        p_status: body.status,
      });
      if (error) {
        console.error("Admin role assignment failed:", error.code);
        return jsonResponse(
          { error: { code: "admin_role_assignment_failed" } },
          409,
        );
      }
      return jsonResponse({ administrator: data });
    }

    case "payments.list":
      return await listPayments(context, body);

    case "payments.review": {
      if (!hasRole(context.role, ["admin"])) {
        return jsonResponse({ error: { code: "insufficient_role" } }, 403);
      }
      const paymentRequestId = body.payment_request_id;
      const decision = body.decision;
      const confirmReceived = body.confirm_received;
      const notes = typeof body.review_notes === "string"
        ? body.review_notes.trim()
        : "";
      if (
        typeof paymentRequestId !== "string" ||
        !uuidPattern.test(paymentRequestId) ||
        (decision !== "approve" && decision !== "reject") ||
        (decision === "approve" && confirmReceived !== true) ||
        (decision === "reject" && (notes.length < 1 || notes.length > 1000)) ||
        notes.length > 1000
      ) {
        return jsonResponse({ error: { code: "invalid_payment_review" } }, 400);
      }

      const { data: review, error: reviewError } = await context.client.rpc(
        "admin_review_premium_payment",
        {
          p_actor_id: context.userId,
          p_payment_request_id: paymentRequestId,
          p_decision: decision,
          p_confirm_received: confirmReceived === true,
          p_review_notes: notes || null,
        },
      );
      if (reviewError || !review) {
        console.error(
          "Admin payment review failed:",
          reviewError?.code ?? "empty_result",
        );
        return jsonResponse({ error: { code: "payment_review_failed" } }, 409);
      }

      if (decision === "approve") {
        return jsonResponse({
          review,
          notification: { status: "in_app" },
        });
      }

      const { data: notification, error: notificationError } = await context
        .client
        .from("payment_email_notifications")
        .select("id")
        .eq("payment_request_id", paymentRequestId)
        .eq("notification_type", "customer_payment_reviewed")
        .maybeSingle();
      if (notificationError) {
        console.error(
          "Customer payment notice lookup failed:",
          notificationError.code,
        );
        return jsonResponse({
          review,
          notification: {
            status: "unknown",
            warning: "delivery_status_unavailable",
          },
        });
      }
      if (!notification) {
        return jsonResponse({
          review,
          notification: { status: "not_configured" },
        });
      }

      const delivery = await deliverPaymentNotification(
        context.client,
        notification.id,
      );
      const deliveryStatus = delivery.delivered
        ? "sent"
        : delivery.errorCode === "notification_already_processing"
        ? "processing"
        : "failed";
      return jsonResponse({
        review,
        notification: {
          status: deliveryStatus,
          ...(delivery.delivered ? {} : { warning: delivery.errorCode }),
        },
      });
    }

    case "plant_catalog.list":
    case "plants.list": {
      if (
        body.action === "plant_catalog.list" &&
        !hasRole(context.role, ["admin"])
      ) {
        return jsonResponse({ error: { code: "insufficient_role" } }, 403);
      }
      const search = typeof body.search === "string" ? body.search.trim() : "";
      const safeLimit = Number.isInteger(body.limit)
        ? Math.max(1, Math.min(Number(body.limit), 100))
        : 50;
      let plants;
      if (search) {
        const pattern = `%${search.replace(/[\\%_]/g, "\\$&")}%`;
        const [scientificResult, commonResult, tagalogResult, bisayaResult] =
          await Promise.all([
            context.client.from("plant_catalog")
              .select("id")
              .ilike("scientific_name", pattern)
              .limit(safeLimit),
            context.client.from("plant_catalog")
              .select("id")
              .ilike("common_name", pattern)
              .limit(safeLimit),
            context.client.from("plant_catalog")
              .select("id")
              .ilike("tagalog_name", pattern)
              .limit(safeLimit),
            context.client.from("plant_catalog")
              .select("id")
              .ilike("bisaya_name", pattern)
              .limit(safeLimit),
          ]);
        if (
          scientificResult.error || commonResult.error || tagalogResult.error ||
          bisayaResult.error
        ) {
          console.error(
            "Plant catalog search failed:",
            scientificResult.error?.code ?? commonResult.error?.code ??
              tagalogResult.error?.code ?? bisayaResult.error?.code,
          );
          return jsonResponse(
            { error: { code: "plant_catalog_unavailable" } },
            503,
          );
        }
        const ids = [
          ...new Set([
            ...(scientificResult.data ?? []).map((plant) => plant.id),
            ...(commonResult.data ?? []).map((plant) => plant.id),
            ...(tagalogResult.data ?? []).map((plant) => plant.id),
            ...(bisayaResult.data ?? []).map((plant) => plant.id),
          ]),
        ];
        if (ids.length === 0) return jsonResponse({ plants: [] });
        const result = await context.client
          .from("plant_catalog")
          .select("*")
          .in("id", ids)
          .order("scientific_name")
          .limit(safeLimit);
        plants = result.data;
        if (result.error) {
          console.error("Plant catalog query failed:", result.error.code);
          return jsonResponse(
            { error: { code: "plant_catalog_unavailable" } },
            503,
          );
        }
      } else {
        const result = await context.client
          .from("plant_catalog")
          .select("*")
          .order("scientific_name")
          .limit(safeLimit);
        plants = result.data;
        if (result.error) {
          console.error("Plant catalog query failed:", result.error.code);
          return jsonResponse(
            { error: { code: "plant_catalog_unavailable" } },
            503,
          );
        }
      }
      const ids = (plants ?? []).map((plant) => plant.id);
      if (ids.length === 0) return jsonResponse({ plants: [] });

      const [careResult, imageResult] = await Promise.all([
        context.client.from("plant_care")
          .select("*")
          .in("plant_id", ids),
        context.client.from("plant_images")
          .select("*")
          .in("plant_id", ids)
          .order("is_primary", { ascending: false }),
      ]);
      if (careResult.error || imageResult.error) {
        console.error(
          "Plant catalog details query failed:",
          careResult.error?.code ?? imageResult.error?.code,
        );
        return jsonResponse(
          { error: { code: "plant_details_unavailable" } },
          503,
        );
      }
      const care = new Map(
        (careResult.data ?? []).map((item) => [item.plant_id, item]),
      );
      const images = new Map<string, typeof imageResult.data>();
      for (const image of imageResult.data ?? []) {
        const existing = images.get(image.plant_id) ?? [];
        existing.push(image);
        images.set(image.plant_id, existing);
      }
      return jsonResponse({
        plants: (plants ?? []).map((plant) => {
          const plantCare = care.get(plant.id) ?? null;
          const plantImages = images.get(plant.id) ?? [];
          const primaryImage = plantImages.find((image) => image.is_primary) ??
            null;
          return {
            ...plant,
            image_url: primaryImage?.image_url ?? "",
            date_updated: plant.date_updated ??
              plant.updated_at?.slice(0, 10) ??
              "",
            field_references: plant.field_references ?? {},
            water_requirement: plantCare?.water_requirements ??
              plantCare?.watering ??
              "",
            sunlight_requirement: plantCare?.sunlight_requirements ??
              plantCare?.sunlight ??
              "",
            soil_requirement: plantCare?.soil_requirements ??
              plantCare?.soil ??
              "",
            fertilizer: plantCare?.fertilizer ?? "",
            growth_tips: plantCare?.growth_tips ?? "",
            common_diseases: plantCare?.common_diseases ?? "",
            treatment: plantCare?.treatment ?? "",
            toxicity: plantCare?.toxicity ?? "unknown",
            care: plantCare,
            images: plantImages,
          };
        }),
      });
    }

    case "plant_catalog.create":
      return await savePlantCatalogRecord(context, body, false);

    case "plant_catalog.update":
      return await savePlantCatalogRecord(context, body, true);

    case "scans.list":
      return await listPlantRecords(context, "plant_identifications");

    case "health.list":
      return await listPlantRecords(context, "plant_health_assessments");

    case "garden.list": {
      if (!hasRole(context.role, ["admin"])) {
        return jsonResponse({ error: { code: "insufficient_role" } }, 403);
      }
      const { data, error } = await context.client
        .from("plants")
        .select(
          "id, owner_id, common_name, scientific_name, family, category, image_path, created_at",
        )
        .order("created_at", { ascending: false })
        .limit(100);
      if (error) {
        console.error("Garden records query failed:", error.code);
        return jsonResponse(
          { error: { code: "garden_records_unavailable" } },
          503,
        );
      }
      return jsonResponse({ plants: data ?? [] });
    }

    case "subscriptions.list": {
      if (!hasRole(context.role, ["admin"])) {
        return jsonResponse({ error: { code: "insufficient_role" } }, 403);
      }
      const { data, error } = await context.client
        .from("subscription_entitlements")
        .select(
          "user_id, product_id, status, expires_at, verified_at, updated_at",
        )
        .order("updated_at", { ascending: false })
        .limit(100);
      if (error) {
        console.error("Subscription query failed:", error.code);
        return jsonResponse({
          error: { code: "subscription_records_unavailable" },
        }, 503);
      }
      return jsonResponse({ subscriptions: data ?? [] });
    }

    case "announcements.list": {
      if (!hasRole(context.role, ["admin"])) {
        return jsonResponse({ error: { code: "insufficient_role" } }, 403);
      }
      const { data, error } = await context.client
        .from("system_announcements")
        .select(
          "id, title, body, category, audience, dismissible, published_at, expires_at, is_active, created_at",
        )
        .order("published_at", { ascending: false })
        .limit(100);
      if (error) {
        console.error("Announcement query failed:", error.code);
        return jsonResponse(
          { error: { code: "announcements_unavailable" } },
          503,
        );
      }
      return jsonResponse({ announcements: data ?? [] });
    }

    case "announcements.create": {
      if (!hasRole(context.role, ["admin"])) {
        return jsonResponse({ error: { code: "insufficient_role" } }, 403);
      }
      const title = typeof body.title === "string" ? body.title.trim() : "";
      const message = typeof body.body === "string" ? body.body.trim() : "";
      const category = body.category;
      const audience = body.audience ?? "all";
      const dismissible = body.dismissible !== false;
      const publishedAt = typeof body.published_at === "string"
        ? body.published_at
        : "";
      const expiresAt = typeof body.expires_at === "string"
        ? body.expires_at
        : "";
      if (
        title.length < 1 || title.length > 120 ||
        message.length < 1 || message.length > 4000 ||
        ![
          "update",
          "maintenance",
          "feature",
          "account",
          "promotion",
          "plant_care",
        ].includes(String(category)) ||
        !["all", "free", "premium"].includes(String(audience)) ||
        !isValidAnnouncementSchedule(publishedAt, expiresAt)
      ) {
        return jsonResponse({ error: { code: "invalid_announcement" } }, 400);
      }

      const { data, error } = await context.client
        .from("system_announcements")
        .insert({
          title,
          body: message,
          category,
          audience,
          dismissible,
          published_at: publishedAt,
          expires_at: expiresAt,
        })
        .select(
          "id, title, category, audience, dismissible, published_at, expires_at, is_active",
        )
        .single();
      if (error) {
        console.error("Announcement creation failed:", error.code);
        return jsonResponse(
          { error: { code: "announcement_create_failed" } },
          503,
        );
      }
      if (
        !await writeAudit(
          context,
          "announcement.created",
          "announcement",
          data.id,
          { category, audience },
        )
      ) {
        return jsonResponse({
          error: { code: "announcement_created_audit_unavailable" },
        }, 503);
      }
      return jsonResponse({
        announcement: data,
        delivery: { status: "published_to_app_feed_only" },
      }, 201);
    }

    default:
      return jsonResponse({ error: { code: "unsupported_admin_action" } }, 404);
  }
}

Deno.serve(handleAdminRequest);
