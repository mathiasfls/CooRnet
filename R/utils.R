clean_urls <- function(df, url){
  df <- df[!grepl("\\.\\.\\.$", df[[url]]),]
  length(df[[url]][grepl("\\.\\.\\.$", df[[url]])]) == 0

  df[[url]] <- gsub("\\?utm_.*", "", df[[url]])
  df[[url]] <- gsub("\\?ref.*", "", df[[url]])
  df[[url]] <- gsub("\\?fbclid.*", "", df[[url]])
  df[[url]] <- gsub("\\?rss.*", "", df[[url]])
  df[[url]] <- gsub("\\?ico.*", "", df[[url]])
  df[[url]] <- gsub("\\?recruiter.*", "", df[[url]])
  df[[url]] <- gsub("\\?sr_share_.*", "", df[[url]])
  df[[url]] <- gsub("\\?fb_rel.*", "", df[[url]])
  df[[url]] <- gsub("\\?social.*", "", df[[url]])
  df[[url]] <- gsub("\\?intcmp_.*", "", df[[url]])
  df[[url]] <- gsub("\\?xrs.*", "", df[[url]])
  df[[url]] <- gsub("\\?CMP.*", "", df[[url]])
  df[[url]] <- gsub("\\?tid.*", "", df[[url]])
  df[[url]] <- gsub("\\?ncid.*", "", df[[url]])
  df[[url]] <- gsub("&utm_.*", "", df[[url]])
  df[[url]] <- gsub("\\?ncid.*", "", df[[url]])
  df[[url]] <- gsub("\\?rbs&utm_hp_ref.*", "", df[[url]])
  df[[url]] <- gsub("/#\\..*", "", df[[url]])
  df[[url]] <- gsub("\\?mobile.*", "", df[[url]])
  df[[url]] <- gsub("&fbclid.*", "", df[[url]])
  df[[url]] <- gsub("/$", "", df[[url]])

  df[[url]] <- gsub(".*(http)", "\\1", df[[url]]) # delete all before "http"
  df[[url]][grepl("^http://127.0.0.1", df[[url]])] <- df[[url]][grepl("^http://127.0.0.1", df[[url]])]
  df <- df[grepl("http://|https://", df[[url]]),] # remove all the entries with the url that does not start with "http"

  return(df)
}

build_coord_graph <- function(ct_shares.df, coordinated_shares, percentile_edge_weight=0.90) {

  ###########################################
  # Get coordinated entities and network ####
  ###########################################

  cat("\nBuilding the graph...")

  el <- coordinated_shares[,c(3,5,4)] # drop unnecesary columns
  el$account.url <- trimws(el$account.url) # remove white space from platform.id
  v1 <- data.frame(node=unique(el$account.url), type=1) # create a dataframe with nodes and type 0=url 1=page
  v2 <- data.frame(node=unique(el$url), type=0)
  v <- rbind(v1,v2)

  g2.bp <- graph.data.frame(el,directed = T, vertices = v) # makes the biap
  g2.bp <- igraph::simplify(g2.bp, remove.multiple = T, remove.loops = T ,edge.attr.comb = "min") # simply the bipartite netwrok to avoid problems with resulting edge weight in projected network
  full_g <- suppressWarnings(bipartite.projection(g2.bp, multiplicity = T)$proj2) # project page-page network

  all_account_info <- ct_shares.df %>%
    group_by(account.url) %>%
    summarize(shares = n(),
              avg.account.subscriberCount=mean(account.subscriberCount))

  # group the pages that changed names
  ct_shares.df <- ct_shares.df %>%
    group_by(account.url) %>%
    mutate(name.changed = ifelse(length(unique(account.name))>1, TRUE, FALSE),
           account.name = paste(unique(account.name), collapse = " | "))

  more.account.info <- ct_shares.df[, c("account.id", "account.name", "name.changed", "account.handle",
                                        "account.url", "account.platform", "account.platformId", "account.verified")]

  rm(ct_shares.df, coordinated_shares)

  more.account.info <- unique(more.account.info)
  all_account_info <- merge(all_account_info, more.account.info, by="account.url")

  # add vertex attributes
  vertex.info <- subset(all_account_info, as.character(all_account_info$account.url) %in% V(full_g)$name)

  V(full_g)$shares <- sapply(V(full_g)$name, function(x) vertex.info$shares[vertex.info$account.url == x])
  V(full_g)$avg.account.subscriberCount <- sapply(V(full_g)$name, function(x) vertex.info$avg.account.subscriberCount[vertex.info$account.url == x])
  V(full_g)$account.platform <- sapply(V(full_g)$name, function(x) vertex.info$account.platform[vertex.info$account.url == x])
  V(full_g)$account.name <- sapply(V(full_g)$name, function(x) vertex.info$account.name[vertex.info$account.url == x])
  V(full_g)$account.verified <- sapply(V(full_g)$name, function(x) vertex.info$account.verified[vertex.info$account.url == x])
  V(full_g)$account.handle <- sapply(V(full_g)$name, function(x) vertex.info$account.handle[vertex.info$account.url == x])




  # keep only highly coordinated entities
  V(full_g)$degree <- degree(full_g)
  q <- quantile(E(full_g)$weight, percentile_edge_weight) # set the percentile_edge_weight number of repetedly coordinated link sharing to keep
  highly_connected_g <- induced_subgraph(graph = full_g, vids = V(full_g)[V(full_g)$degree > 0 ]) # filter for degree
  highly_connected_g <- subgraph.edges(highly_connected_g, eids = which(E(highly_connected_g)$weight >= q),delete.vertices = T) # filter for edge weight


  # timestamp of coordinated sharing as edge atribute

  shared <- V(g2.bp)[V(g2.bp)$type==0]
  highly_connected_g <-  set.edge.attribute(graph = highly_connected_g,name = "t_coord_share",value = 0)
  for (v in 1:length(shared)){
    timestamps <- incident(g2.bp,v = V(g2.bp)[V(g2.bp)$name==shared[v]$name])$share_date
    n <- neighbors(g2.bp,v = V(g2.bp)[V(g2.bp)$name==shared[v]$name],mode = "in")
    n <- n[n$name %in% V(highly_connected_g)$name]
    n <- n$name
    if(length(n) >0){
      edges <- expand.grid(n,n)
      edges <- edges[edges$Var1 != edges$Var2,]
      edges <- edges[!duplicated(t(apply(edges, 1, sort))),]
      if(nrow(edges) >0){
        for (e in 1:nrow(edges)){
          e_h <- get.edge.ids(highly_connected_g, c(as.character(edges[e,1]), as.character(edges[e,2])))

          if(e_h != 0){
          if (E(highly_connected_g)[e_h]$t_coord_share != 0){E(highly_connected_g)[e_h]$t_coord_share <-  paste(E(highly_connected_g)[e_h]$t_coord_share,min(timestamps),sep = ";")}
          if (E(highly_connected_g)[e_h]$t_coord_share == 0){E(highly_connected_g)[e_h]$t_coord_share <-  min(timestamps)}
          }
        }
      }
    }
  }
  E(highly_connected_g)$t_coord_share <- strsplit(E(highly_connected_g)$t_coord_share,";")



  # find and annotate nodes-components
  V(highly_connected_g)$component <- components(highly_connected_g)$membership

  highly_connected_coordinated_entities <- igraph::as_data_frame(highly_connected_g, "vertices")
  rownames(highly_connected_coordinated_entities) <- 1:nrow(highly_connected_coordinated_entities)
  colnames(more.account.info)[5] <- "name" # please use column name and not number
  highly_connected_coordinated_entities <- merge(highly_connected_coordinated_entities, unique(more.account.info[, c("name", "name.changed")]), by="name", all.x=T)
  highly_connected_coordinated_entities <- highly_connected_coordinated_entities[, c(1:5,10,6:9)]

  highly_c_list <- list(highly_connected_g, highly_connected_coordinated_entities, q)

  cat("\nDone!")

  return(highly_c_list)

}
